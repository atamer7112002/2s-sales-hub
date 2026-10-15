import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../../features/customers/domain/customer.dart';
import '../network/odoo_api.dart';
import '../sync/phone_operation.dart';

abstract interface class CustomerCache {
  Future<void> save(String scope, List<Customer> customers);
  Future<List<Customer>> read(
    String scope,
    String query,
    int offset,
    int limit,
  );
  Future<Customer?> get(String scope, int id);
  Future<void> clear(String scope);
}

/// Version 2 adds a transactional, credential-free outbox to the existing cache.
class SqliteCustomerCache implements CustomerCache {
  SqliteCustomerCache({this.path, this.factory});
  final String? path;
  final DatabaseFactory? factory;
  Future<Database>? _opening;
  Future<Database> get db => _opening ??= _open();
  Future<Database> _open() async => (factory ?? databaseFactory).openDatabase(
    path ?? p.join(await getDatabasesPath(), 'sales_hub.db'),
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE customers(scope TEXT NOT NULL,id INTEGER NOT NULL,name TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(scope,id))',
        );
        await _outbox(db);
      },
      onUpgrade: (db, old, _) async {
        if (old < 2) {
          await _outbox(db);
        }
      },
    ),
  );
  static Future<void> _outbox(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE phone_outbox(scope TEXT NOT NULL,customer_id INTEGER NOT NULL,operation_id TEXT NOT NULL UNIQUE,phone TEXT NOT NULL,base_phone TEXT NOT NULL,created_at INTEGER NOT NULL,status TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_at INTEGER NOT NULL DEFAULT 0,last_error TEXT,error_kind TEXT,lease_token TEXT,lease_until INTEGER NOT NULL DEFAULT 0,force_write INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(scope,customer_id))',
    );
    await db.execute(
      'CREATE INDEX phone_outbox_due ON phone_outbox(scope,status,next_at)',
    );
  }

  static String token() =>
      '${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  Future<void> close() async {
    if (_opening != null) {
      await (await db).close();
      _opening = null;
    }
  }

  Future<Customer> _decode(
    DatabaseExecutor tx,
    Map<String, Object?> row,
  ) async {
    final c = Customer.fromJson(jsonDecode(row['data'] as String));
    final ops = await tx.query(
      'phone_outbox',
      where: 'scope=? AND customer_id=?',
      whereArgs: [row['scope'], c.id],
    );
    if (ops.isEmpty) {
      return c;
    }
    final op = PhoneOperation.fromRow(ops.single);
    return c.withSync(
      op.status == 'synced' ? c.phone : op.phone,
      op.status,
      op.error,
    );
  }

  @override
  Future<void> save(String scope, List<Customer> customers) async {
    await (await db).transaction((tx) async {
      for (final c in customers) {
        await tx.insert('customers', {
          'scope': scope,
          'id': c.id,
          'name': c.name,
          'data': jsonEncode(c.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<List<Customer>> read(
    String scope,
    String query,
    int offset,
    int limit,
  ) async {
    final database = await db;
    return database.transaction((tx) async {
      final rows = await tx.query(
        'customers',
        where: 'scope=? AND instr(lower(name),lower(?))>0',
        whereArgs: [scope, query],
        orderBy: 'name COLLATE NOCASE,id',
        offset: offset,
        limit: limit,
      );
      return Future.wait(rows.map((row) => _decode(tx, row)));
    });
  }

  @override
  Future<Customer?> get(String scope, int id) async =>
      (await db).transaction((tx) async {
        final rows = await tx.query(
          'customers',
          where: 'scope=? AND id=?',
          whereArgs: [scope, id],
        );
        return rows.isEmpty ? null : _decode(tx, rows.single);
      });
  Future<void> enqueue(String scope, int id, String phone, int now) async {
    if (validatePhone(phone) != null) {
      throw AppFailure(validatePhone(phone)!);
    }
    await (await db).transaction((tx) async {
      final rows = await tx.query(
        'customers',
        where: 'scope=? AND id=?',
        whereArgs: [scope, id],
      );
      if (rows.isEmpty) {
        throw const AppFailure(
          'Open this customer online once before editing offline.',
        );
      }
      final c = Customer.fromJson(jsonDecode(rows.single['data'] as String));
      final existing = await tx.query(
        'phone_outbox',
        where: 'scope=? AND customer_id=?',
        whereArgs: [scope, id],
      );
      final previous = existing.isEmpty
          ? null
          : PhoneOperation.fromRow(existing.single);
      final base = previous != null && previous.status != 'synced'
          ? previous.basePhone
          : c.phone;
      await tx.insert('phone_outbox', {
        'scope': scope,
        'customer_id': id,
        'operation_id': token(),
        'phone': phone.trim(),
        'base_phone': base,
        'created_at': now,
        'status': 'pending',
        'attempts': 0,
        'next_at': now,
        'lease_until': 0,
        'force_write': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'customers',
        {
          'data': jsonEncode(
            c.withSync(phone.trim(), 'pending', null).toJson(),
          ),
        },
        where: 'scope=? AND id=?',
        whereArgs: [scope, id],
      );
    });
  }

  Future<List<PhoneOperation>> operations(String scope) async =>
      (await (await db).query(
        'phone_outbox',
        where: 'scope=?',
        whereArgs: [scope],
        orderBy: 'created_at,customer_id',
      )).map(PhoneOperation.fromRow).toList();
  Future<PhoneOperation?> claim(String scope, int now) async =>
      (await db).transaction((tx) async {
        await tx.rawUpdate(
          "UPDATE phone_outbox SET status=CASE WHEN attempts<5 THEN 'pending' ELSE 'failed' END, lease_token=NULL,last_error='Previous sync was interrupted. Retrying safely.',error_kind='interrupted' WHERE scope=? AND status='syncing' AND lease_until<=?",
          [scope, now],
        );
        final rows = await tx.query(
          'phone_outbox',
          where: "scope=? AND status='pending' AND next_at<=? AND attempts<5",
          whereArgs: [scope, now],
          orderBy: 'created_at,customer_id',
          limit: 1,
        );
        if (rows.isEmpty) {
          return null;
        }
        final row = Map<String, Object?>.from(rows.single);
        row.addAll({
          'status': 'syncing',
          'attempts': (row['attempts'] as int) + 1,
          'lease_token': token(),
          'lease_until': now + 300000,
        });
        await tx.update(
          'phone_outbox',
          row,
          where: 'scope=? AND operation_id=?',
          whereArgs: [scope, row['operation_id']],
        );
        return PhoneOperation.fromRow(row);
      });
  Future<bool> current(PhoneOperation op) async => (await (await db).query(
    'phone_outbox',
    columns: ['operation_id'],
    where: "scope=? AND operation_id=? AND lease_token=? AND status='syncing'",
    whereArgs: [op.scope, op.id, op.leaseToken],
  )).isNotEmpty;
  Future<void> complete(PhoneOperation op) async {
    await (await db).transaction((tx) async {
      final changed = await tx.update(
        'phone_outbox',
        {
          'status': 'synced',
          'last_error': null,
          'error_kind': null,
          'lease_token': null,
          'lease_until': 0,
        },
        where:
            "scope=? AND operation_id=? AND lease_token=? AND status='syncing'",
        whereArgs: [op.scope, op.id, op.leaseToken],
      );
      if (changed == 1) {
        final rows = await tx.query(
          'customers',
          where: 'scope=? AND id=?',
          whereArgs: [op.scope, op.customerId],
        );
        if (rows.isNotEmpty) {
          final c = Customer.fromJson(
            jsonDecode(rows.single['data'] as String),
          );
          await tx.update(
            'customers',
            {'data': jsonEncode(c.withSync(op.phone, 'synced', null).toJson())},
            where: 'scope=? AND id=?',
            whereArgs: [op.scope, op.customerId],
          );
        }
      } else {
        // A newer local edit superseded an in-flight write. Advance its baseline.
        await tx.rawUpdate(
          "UPDATE phone_outbox SET base_phone=? WHERE scope=? AND customer_id=? AND operation_id<>? AND status<>'synced' AND base_phone=?",
          [op.phone, op.scope, op.customerId, op.id, op.basePhone],
        );
      }
    });
  }

  Future<void> fail(PhoneOperation op, AppFailure failure, int now) async {
    final retry = failure.retryable && op.attempts < 5;
    final delay = min(300, 5 * (1 << op.attempts));
    await (await db).update(
      'phone_outbox',
      {
        'status': retry ? 'pending' : 'failed',
        'next_at': now + delay * 1000,
        'last_error': failure.message,
        'error_kind': failure.kind.name,
        'lease_token': null,
        'lease_until': 0,
      },
      where: 'scope=? AND operation_id=? AND lease_token=?',
      whereArgs: [op.scope, op.id, op.leaseToken],
    );
  }

  Future<void> retry(
    String scope, {
    bool overrideConflicts = false,
    bool authenticationOnly = false,
  }) async {
    await (await db).rawUpdate(
      "UPDATE phone_outbox SET status='pending',attempts=0,next_at=0,last_error=NULL,lease_token=NULL,force_write=CASE WHEN error_kind='conflict' AND ?=1 THEN 1 ELSE force_write END WHERE scope=? AND status='failed' AND (?=0 OR error_kind='authentication') AND (error_kind<>'conflict' OR ?=1)",
      [
        overrideConflicts ? 1 : 0,
        scope,
        authenticationOnly ? 1 : 0,
        overrideConflicts ? 1 : 0,
      ],
    );
  }

  Future<void> blockPending(String scope, AppFailure failure) async {
    await (await db).update(
      'phone_outbox',
      {
        'status': 'failed',
        'last_error': failure.message,
        'error_kind': failure.kind.name,
      },
      where: "scope=? AND status='pending'",
      whereArgs: [scope],
    );
  }

  /// Sign-out retains only unsynchronized records, without any credentials.
  Future<void> retainPending(String scope) async {
    await (await db).transaction((tx) async {
      await tx.delete(
        'phone_outbox',
        where: "scope=? AND status='synced'",
        whereArgs: [scope],
      );
      await tx.rawDelete(
        'DELETE FROM customers WHERE scope=? AND id NOT IN (SELECT customer_id FROM phone_outbox WHERE scope=?)',
        [scope, scope],
      );
    });
  }

  /// Explicit permanent account-data removal; caller must obtain confirmation.
  @override
  Future<void> clear(String scope) async {
    await (await db).transaction((tx) async {
      await tx.delete('phone_outbox', where: 'scope=?', whereArgs: [scope]);
      await tx.delete('customers', where: 'scope=?', whereArgs: [scope]);
    });
  }
}
