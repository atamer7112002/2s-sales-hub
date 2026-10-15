// Run only through check_offline_odoo.command; never part of normal unit tests.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/core/sync/phone_sync.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/customers/data/customer_repository.dart';

class OfflineGate implements OdooApi {
  OfflineGate(this.real);
  final OdooApi real;
  bool offline = false;
  @override
  Future<int> authenticate(OdooConfig c, String u, String p) =>
      real.authenticate(c, u, p);
  @override
  Future<dynamic> execute(
    OdooConfig c,
    int uid,
    String password,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) {
    if (offline) {
      throw const AppFailure('Simulated offline transport', offline: true);
    }
    return real.execute(c, uid, password, model, method, args, kwargs);
  }
}

void main() {
  test('real Online offline edit, SQLite restart and verified synchronization', () async {
    final report = <String, dynamic>{
      'server': 'https://2s-sales-demo.odoo.com',
      'database': '2s-sales-demo',
      'checked_at_utc': DateTime.now().toUtc().toIso8601String(),
      'status': 'in_progress',
    };
    Directory? temp;
    SqliteCustomerCache? store;
    PhoneSync? sync;
    Session? session;
    int? customerId;
    final api = OfflineGate(
      XmlRpcOdooApi(
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 20),
          ),
        ),
      ),
    );
    String stage = 'secure local input';
    Future<dynamic> call(
      String model,
      String method,
      List<dynamic> args, [
      Map<String, dynamic> kw = const {},
    ]) => api.execute(
      session!.config,
      session.uid,
      session.password,
      model,
      method,
      args,
      kw,
    );
    try {
      final path = Platform.environment['TWO_S_CREDENTIAL_SOCKET'];
      if (path == null) {
        throw StateError('Launch using the secure local prompt.');
      }
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final raw = await socket.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      await socket.close();
      final creds = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final config = OdooConfig(
        'https://2s-sales-demo.odoo.com',
        '2s-sales-demo',
      );
      stage = 'authenticate';
      final uid = await api.authenticate(
        config,
        creds['login'],
        creds['password'],
      );
      session = Session(config, uid, creds['login'], creds['password'], true);
      stage = 'create synthetic customer';
      customerId = await call('res.partner', 'create', [
        {
          'name':
              '2S Offline Verification ${DateTime.now().microsecondsSinceEpoch}',
          'customer_rank': 1,
          'phone': '11111',
        },
      ]);
      sqfliteFfiInit();
      temp = await Directory.systemTemp.createTemp('2s-live-offline-');
      final dbPath = '${temp.path}/cache.db';
      store = SqliteCustomerCache(path: dbPath, factory: databaseFactoryFfi);
      sync = PhoneSync(api, store);
      await sync.setSession(session);
      await sync.synchronize();
      final repo = OdooCustomerRepository(api, session, store, sync: sync);
      stage = 'cache customer';
      await repo.get(customerId!);
      report['cache'] = 'passed';
      api.offline = true;
      sync.connectionChanged(false);
      stage = 'offline edit';
      await repo.updatePhone(customerId, '22222');
      await sync.synchronize();
      final pending = (await store.operations(session.scope)).single;
      if (pending.status != 'pending' ||
          (await store.get(session.scope, customerId))!.phone != '22222') {
        throw StateError('Offline queue assertion failed');
      }
      report['offline_edit_and_durable_queue'] = 'passed';
      stage = 'close and reopen SQLite';
      await sync.setSession(null);
      sync.dispose();
      await store.close();
      store = SqliteCustomerCache(path: dbPath, factory: databaseFactoryFfi);
      sync = PhoneSync(api, store);
      await sync.setSession(session);
      await sync.synchronize();
      if ((await store.operations(session.scope)).single.status != 'pending') {
        throw StateError('Restart assertion failed');
      }
      report['sqlite_restart'] = 'passed';
      stage = 'restore connection and synchronize';
      api.offline = false;
      sync.connectionChanged(true);
      await sync.synchronize();
      if ((await store.operations(session.scope)).single.status != 'synced') {
        throw StateError('Synchronization assertion failed');
      }
      final rows = await call(
        'res.partner',
        'read',
        [
          [customerId],
        ],
        {
          'fields': ['phone'],
        },
      ) as List;
      if (rows.single['phone'] != '22222') {
        throw StateError('Server readback assertion failed');
      }
      report['real_odoo_write_and_readback'] = 'passed';
      report['status'] = 'passed';
    } catch (e) {
      report['status'] = 'failed';
      report['failure_stage'] = stage;
      report['failure_type'] = e.runtimeType.toString();
    } finally {
      if (sync != null) {
        await sync.setSession(null);
        sync.dispose();
      }
      if (store != null) {
        await store.close();
      }
      api.offline = false;
      if (customerId != null && session != null) {
        try {
          await call('res.partner', 'unlink', [
            [customerId],
          ]);
          report['synthetic_cleanup'] = 'passed';
        } catch (_) {
          report['synthetic_cleanup'] = 'failed';
          report['cleanup_customer_id'] = customerId;
          report['status'] = 'failed';
        }
      }
      if (temp != null) {
        await temp.delete(recursive: true);
      }
      await File('docs/offline_live_verification.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
    expect(
      report['status'],
      'passed',
      reason: 'See sanitized docs/offline_live_verification.json. Credentials and raw faults are never logged.',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
