import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/customer_cache.dart';
import '../network/odoo_api.dart';
import '../../features/authentication/domain/session.dart';
import '../../features/customers/domain/customer.dart';

/// One foreground worker. SQLite claims and leases also guard crash recovery.
class PhoneSync extends ChangeNotifier {
  PhoneSync(this.api, this.store, {int Function()? clock})
    : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);
  final OdooApi api;
  final SqliteCustomerCache store;
  final int Function() clock;
  Session? _session;
  Session? get session => _session;
  Future<void>? _running;
  bool offline = false, busy = false;
  String? error;
  int outstanding = 0;
  bool _enabled = true;
  Future<void> setSession(Session? session) async {
    _enabled = false;
    await _running;
    _session = session;
    _enabled = true;
    offline = false;
    error = null;
    outstanding = 0;
    try {
      if (session != null) {
        // Auth failures can resume only after a fresh, verified login.
        if (session.onlineVerified) {
          await store.retry(session.scope, authenticationOnly: true);
        }
        await refresh();
        unawaited(synchronize());
      } else {
        notifyListeners();
      }
    } catch (_) {
      error = 'Saved edits are unavailable right now. Please retry.';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final s = _session;
    if (s == null) {
      return;
    }
    try {
      final rows = await store.operations(s.scope);
      if (identical(s, _session)) {
        outstanding = rows.where((r) => r.status != 'synced').length;
        notifyListeners();
      }
    } catch (_) {
      error = 'Unable to read saved edits. Please retry.';
      notifyListeners();
    }
  }

  Future<void> savePhone(String scope, int id, String phone) async {
    final s = _session;
    if (s == null || !_enabled || s.scope != scope) {
      throw const AppFailure(
        'Sign in with the original account before editing.',
      );
    }
    try {
      await store.enqueue(s.scope, id, phone, clock());
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        'Unable to save on this device. Check available space and retry.',
      );
    }
    await refresh();
    unawaited(synchronize());
  }

  Future<void> retry({bool overrideConflicts = false, String? scope}) async {
    final s = _session;
    if (s == null) {
      return;
    }
    if (scope != null && scope != s.scope) {
      return;
    }
    try {
      await store.retry(s.scope, overrideConflicts: overrideConflicts);
      await refresh();
      await synchronize();
    } catch (_) {
      error = 'Unable to retry right now. Saved edits are retained.';
      notifyListeners();
    }
  }

  Future<void> synchronize() {
    if (!_enabled || _session == null) {
      return Future.value();
    }
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<dynamic> _call(
    Session s,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kw = const {},
  ]) => api.execute(s.config, s.uid, s.password, model, method, args, kw);
  Future<String> _phone(Session s, int id) async {
    final rows = await _call(
      s,
      'res.partner',
      'search_read',
      [
        [
          ['id', '=', id],
          ['customer_rank', '>', 0],
        ],
      ],
      {
        'fields': ['phone'],
        'limit': 1,
      },
    ) as List;
    if (rows.isEmpty) {
      throw const AppFailure(
        'This customer is unavailable or access was removed.',
        kind: FailureKind.permission,
      );
    }
    return odooText(rows.single['phone']);
  }

  Future<void> _run() async {
    final s = _session!;
    busy = true;
    notifyListeners();
    try {
      // A connectivity event alone never proves server reachability or authorization.
      try {
        await _call(
          s,
          'res.users',
          'read',
          [
            [s.uid],
          ],
          {
            'fields': ['id'],
          },
        );
        offline = false;
        error = null;
      } on AppFailure catch (e) {
        offline = e.retryable;
        error = e.message;
        if (!e.retryable) {
          await store.blockPending(s.scope, e);
        }
        return;
      }
      while (_enabled && identical(s, _session)) {
        final op = await store.claim(s.scope, clock());
        if (op == null) {
          break;
        }
        await refresh();
        try {
          final remote = await _phone(s, op.customerId);
          if (!await store.current(op)) {
            continue;
          }
          if (remote != op.phone) {
            if (!op.force && remote != op.basePhone) {
              throw const AppFailure(
                'Sync conflict: the phone changed in Odoo. Review before applying your saved edit.',
                kind: FailureKind.conflict,
              );
            }
            final acknowledged = await _call(s, 'res.partner', 'write', [
              [op.customerId],
              {'phone': op.phone},
            ]);
            if (acknowledged != true) {
              throw const AppFailure(
                'Odoo did not acknowledge the phone update.',
              );
            }
            if (await _phone(s, op.customerId) != op.phone) {
              throw const AppFailure(
                'Sync conflict: Odoo returned a different phone after saving. Review before retrying.',
                kind: FailureKind.conflict,
              );
            }
          }
          // On recovery a matching read avoids replaying an already persisted write.
          await store.complete(op);
        } on AppFailure catch (e) {
          await store.fail(op, e, clock());
          error = e.message;
          offline = e.offline;
          if (e.kind == FailureKind.authentication) {
            await store.blockPending(s.scope, e);
            break;
          }
          if (e.retryable) {
            break;
          }
        } catch (_) {
          // A local acknowledgement failure leaves the durable claim recoverable.
          error =
              'Sync was interrupted. Saved edits are retained for safe retry.';
          break;
        } finally {
          await refresh();
        }
      }
    } on AppFailure catch (e) {
      error = e.message;
      offline = e.offline;
    } catch (_) {
      error = 'Sync is temporarily unavailable. Your saved edits are retained.';
    } finally {
      busy = false;
      await refresh();
    }
  }

  void connectionChanged(bool available) {
    offline = !available;
    notifyListeners();
    if (available) {
      unawaited(synchronize());
    }
  }
}
