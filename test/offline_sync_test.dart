import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/core/sync/phone_sync.dart';
import 'package:task_2s_egypt/core/sync/phone_operation.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/customers/data/customer_repository.dart';
import 'package:task_2s_egypt/features/customers/domain/customer.dart';

class SyncApi implements OdooApi {
  bool offline = true, authExpired = false, conflictAfterWrite = false;
  String remote = '11111';
  int writes = 0;
  AppFailure? writeFailure;
  Completer<void>? writeGate;
  final scopes = <String>[];
  @override
  Future<int> authenticate(OdooConfig c, String u, String p) async => 1;
  @override
  Future<dynamic> execute(
    OdooConfig c,
    int uid,
    String password,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) async {
    scopes.add('${c.server}|${c.database}|$uid');
    if (offline) {
      throw const AppFailure('Offline', offline: true);
    }
    if (authExpired) {
      throw const AppFailure('Sign in again', kind: FailureKind.authentication);
    }
    if (model == 'res.users') {
      return [
        {'id': uid},
      ];
    }
    if (method == 'write') {
      writes++;
      if (writeFailure != null) {
        throw writeFailure!;
      }
      remote = (args[1] as Map)['phone'];
      if (writeGate != null) {
        await writeGate!.future;
      }
      if (conflictAfterWrite) {
        remote = '99999';
      }
      return true;
    }
    return [
      {'id': 1, 'name': 'Demo', 'phone': remote},
    ];
  }
}

class AckFailStore extends SqliteCustomerCache {
  AckFailStore({required super.path, required super.factory});
  @override
  Future<void> complete(PhoneOperation op) async {
    throw StateError('simulated local acknowledgement failure');
  }
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteCustomerCache store;
  late SyncApi api;
  late PhoneSync sync;
  int now = 1000000;
  final session = Session(
    OdooConfig('https://example.com', 'db'),
    1,
    'local-user',
    'test-only',
    true,
  );
  Future<void> drain() async {
    await sync.synchronize();
  }

  Future<void> edit([String phone = '22222']) async {
    await sync.savePhone(session.scope, 1, phone);
    await drain();
  }

  Future<PhoneOperation> operation() async =>
      (await store.operations(session.scope)).single;
  setUp(() async {
    now = 1000000;
    dir = await Directory.systemTemp.createTemp('sales-sync-test-');
    store = SqliteCustomerCache(
      path: '${dir.path}/cache.db',
      factory: databaseFactoryFfi,
    );
    api = SyncApi();
    sync = PhoneSync(api, store, clock: () => now);
    await store.save(session.scope, [
      const Customer(id: 1, name: 'Demo', phone: '11111'),
    ]);
    await sync.setSession(session);
    await drain();
  });
  tearDown(() async {
    await sync.setSession(null);
    sync.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });
  test('offline edit validates, atomically updates cache and queues without credentials', () async {
    await edit();
    final c = await store.get(session.scope, 1);
    expect(c!.phone, '22222');
    expect(c.syncStatus, 'pending');
    final op = await operation();
    expect(op.basePhone, '11111');
    expect(op.id, isNotEmpty);
    expect(op.createdAt, now);
    expect(op.attempts, 0);
    final cols = await (await store.db).rawQuery(
      'PRAGMA table_info(phone_outbox)',
    );
    expect(cols.any((c) => c['name'].toString().contains('password')), false);
    expect(
      () => sync.savePhone(session.scope, 1, 'invalid'),
      throwsA(isA<AppFailure>()),
    );
  });
  test('pending edit survives actual database close and reopen', () async {
    await edit();
    await store.close();
    store = SqliteCustomerCache(
      path: '${dir.path}/cache.db',
      factory: databaseFactoryFfi,
    );
    expect((await store.get(session.scope, 1))!.phone, '22222');
    expect((await operation()).status, 'pending');
  });
  test(
    'multiple edits coalesce latest value while preserving original baseline',
    () async {
      await edit('22222');
      final first = (await operation()).id;
      await edit('33333');
      expect((await store.operations(session.scope)).length, 1);
      expect((await operation()).id, isNot(first));
      expect((await operation()).basePhone, '11111');
      expect((await operation()).phone, '33333');
    },
  );
  test('reconnect verifies reachability then writes and reads back', () async {
    await edit();
    api.offline = false;
    sync.connectionChanged(true);
    await drain();
    expect(api.remote, '22222');
    expect((await operation()).status, 'synced');
    expect((await store.get(session.scope, 1))!.syncStatus, 'synced');
  });
  test('temporary write failure backs off and later retry succeeds', () async {
    await edit();
    api.offline = false;
    api.writeFailure = const AppFailure('Network timeout', offline: true);
    await drain();
    final failed = await operation();
    expect(failed.status, 'pending');
    expect(failed.attempts, 1);
    expect(failed.nextAt, greaterThan(now));
    await drain();
    expect(api.writes, 1);
    now = failed.nextAt;
    api.writeFailure = null;
    await drain();
    expect((await operation()).status, 'synced');
  });
  test(
    'automatic retries stop at five and manual retry remains recoverable',
    () async {
      await edit();
      api.offline = false;
      api.writeFailure = const AppFailure('timeout', offline: true);
      for (var i = 0; i < 5; i++) {
        await drain();
        now = (await operation()).nextAt;
      }
      expect((await operation()).status, 'failed');
      expect(api.writes, 5);
      await drain();
      expect(api.writes, 5);
      api.writeFailure = null;
      await sync.retry();
      expect((await operation()).status, 'synced');
    },
  );
  test('authentication expiration retains edits until original account reauthenticates', () async {
    await edit();
    api.offline = false;
    api.authExpired = true;
    await drain();
    expect((await operation()).status, 'failed');
    expect((await operation()).kind, 'authentication');
    await sync.setSession(null);
    api.authExpired = false;
    await sync.setSession(session);
    await drain();
    expect((await operation()).status, 'synced');
  });
  test(
    'permission denied is visible and never retried automatically',
    () async {
      await edit();
      api.offline = false;
      api.writeFailure = const AppFailure(
        'No phone write permission',
        kind: FailureKind.permission,
      );
      await drain();
      expect((await operation()).status, 'failed');
      expect((await operation()).kind, 'permission');
      await drain();
      expect(api.writes, 1);
    },
  );
  test(
    'same UID in another database or server never receives queued edits',
    () async {
      await edit();
      api.offline = false;
      for (final c in [
        OdooConfig('https://example.com', 'other-db'),
        OdooConfig('https://another.example.com', 'db'),
      ]) {
        await sync.setSession(Session(c, 1, 'other', 'test', true));
        await drain();
        expect(api.writes, 0);
      }
      await sync.setSession(Session(session.config, 2, 'other', 'test', true));
      await drain();
      expect(api.writes, 0);
      expect((await operation()).status, 'pending');
      expect(
        () => sync.savePhone(session.scope, 1, '33333'),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test(
    'atomic claims prevent two workers from claiming the same operation',
    () async {
      await edit();
      final claims = await Future.wait([
        store.claim(session.scope, now),
        store.claim(session.scope, now),
      ]);
      expect(claims.whereType<PhoneOperation>().length, 1);
    },
  );
  test('server success then local ack failure recovers after restart without duplicate write', () async {
    await sync.setSession(null);
    await store.close();
    store = AckFailStore(
      path: '${dir.path}/cache.db',
      factory: databaseFactoryFfi,
    );
    sync.dispose();
    sync = PhoneSync(api, store, clock: () => now);
    await sync.setSession(session);
    await drain();
    await edit();
    api.offline = false;
    await drain();
    expect(api.writes, 1);
    expect((await operation()).status, 'syncing');
    await sync.setSession(null);
    sync.dispose();
    await store.close();
    now += 300001;
    store = SqliteCustomerCache(
      path: '${dir.path}/cache.db',
      factory: databaseFactoryFfi,
    );
    sync = PhoneSync(api, store, clock: () => now);
    await sync.setSession(session);
    await drain();
    expect((await operation()).status, 'synced');
    expect(api.writes, 1);
  });
  test(
    'server readback mismatch surfaces a conflict and preserves local phone',
    () async {
      await edit();
      api.offline = false;
      api.conflictAfterWrite = true;
      await drain();
      expect((await operation()).kind, 'conflict');
      expect((await operation()).status, 'failed');
      expect((await store.get(session.scope, 1))!.phone, '22222');
    },
  );
  test(
    'remote changes are protected until explicit conflict override',
    () async {
      await edit();
      api.offline = false;
      api.remote = '44444';
      await drain();
      expect(api.writes, 0);
      expect((await operation()).kind, 'conflict');
      await sync.retry();
      expect(api.writes, 0);
      await sync.retry(overrideConflicts: true);
      expect(api.remote, '22222');
      expect((await operation()).status, 'synced');
    },
  );
  test('server refresh does not overwrite pending local edits', () async {
    await edit();
    api.offline = false;
    final repo = OdooCustomerRepository(api, session, store, sync: sync);
    final page = await repo.list();
    expect(page.items.single.phone, '22222');
    expect(page.items.single.syncStatus, 'pending');
    expect((await repo.get(1)).phone, '22222');
  });
  test(
    'new edit during an in-flight write stays queued and is applied next',
    () async {
      await edit();
      api.offline = false;
      api.writeGate = Completer<void>();
      final work = sync.synchronize();
      while (api.writes == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await sync.savePhone(session.scope, 1, '33333');
      api.writeGate!.complete();
      await work;
      expect(api.remote, '33333');
      expect((await operation()).status, 'synced');
    },
  );
  test('normal signout retention keeps pending edits; explicit removal deletes them', () async {
    await edit();
    await store.save('other', [const Customer(id: 2, name: 'Other')]);
    await store.retainPending(session.scope);
    expect((await operation()).status, 'pending');
    expect((await store.get(session.scope, 1))!.phone, '22222');
    await store.clear(session.scope);
    expect(await store.operations(session.scope), isEmpty);
    expect(await store.get(session.scope, 1), isNull);
    expect(await store.get('other', 2), isNotNull);
  });
  test('version-one cache migrates without losing customers', () async {
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE customers(scope TEXT NOT NULL,id INTEGER NOT NULL,name TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(scope,id))',
          );
        },
      ),
    );
    await old.close();
    final migrated = SqliteCustomerCache(
      path: path,
      factory: databaseFactoryFfi,
    );
    await migrated.save(session.scope, [const Customer(id: 1, name: 'Demo')]);
    await migrated.enqueue(session.scope, 1, '12345', now);
    expect((await migrated.operations(session.scope)).single.status, 'pending');
    await migrated.close();
  });
}
