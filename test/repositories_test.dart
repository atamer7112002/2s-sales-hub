import 'package:flutter_test/flutter_test.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/customers/domain/customer.dart';
import 'package:task_2s_egypt/features/customers/data/customer_repository.dart';
import 'package:task_2s_egypt/features/sales_orders/data/sales_order_repository.dart';

class ApiFixture implements OdooApi {
  late Future<dynamic> Function(
    String model,
    String method,
    List<dynamic> args,
    Map<String, dynamic> kw,
  )
  handler;
  @override
  Future<int> authenticate(
    OdooConfig config,
    String username,
    String password,
  ) async => 1;
  @override
  Future<dynamic> execute(
    OdooConfig config,
    int uid,
    String password,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) => handler(model, method, args, kwargs);
}

class CacheFixture implements CustomerCache {
  final rows = <String, Map<int, Customer>>{};
  @override
  Future<void> save(String scope, List<Customer> items) async {
    for (final c in items) {
      (rows[scope] ??= {})[c.id] = c;
    }
  }

  @override
  Future<List<Customer>> read(
    String scope,
    String query,
    int offset,
    int limit,
  ) async => (rows[scope]?.values ?? <Customer>[])
      .where((c) => c.name.contains(query))
      .skip(offset)
      .take(limit)
      .toList();
  @override
  Future<Customer?> get(String scope, int id) async => rows[scope]?[id];
  @override
  Future<void> clear(String scope) async {
    rows.remove(scope);
  }
}

void main() {
  final session = Session(
    OdooConfig('https://example.com', 'db'),
    1,
    'user',
    'secret',
    true,
  );
  late ApiFixture api;
  late CacheFixture cache;
  setUp(() {
    api = ApiFixture();
    cache = CacheFixture();
  });
  test('customer domain search and pagination are sent to server', () async {
    api.handler = (model, method, args, kw) async {
      expect(model, 'res.partner');
      expect(
        args.first,
        containsAll([
          ['customer_rank', '>', 0],
          ['name', 'ilike', 'Ali'],
        ]),
      );
      expect(kw['offset'], 20);
      expect(kw['limit'], 20);
      return <dynamic>[];
    };
    final result = await OdooCustomerRepository(
      api,
      session,
      cache,
    ).list(query: 'Ali', offset: 20);
    expect(result.items, isEmpty);
    expect(result.hasMore, false);
  });
  test('offline reads cached records within account scope', () async {
    await cache.save(session.scope, [const Customer(id: 1, name: 'Ali')]);
    await cache.save('other-account', [const Customer(id: 2, name: 'Private')]);
    api.handler = (_, _, _, _) async =>
        throw const AppFailure('offline', offline: true);
    final result = await OdooCustomerRepository(api, session, cache).list();
    expect(result.offline, true);
    expect(result.items.single.name, 'Ali');
  });
  test('access failures never fall back to stale cached records', () async {
    await cache.save(session.scope, [const Customer(id: 1, name: 'Ali')]);
    api.handler = (_, _, _, _) async => throw const AppFailure('Access denied');
    expect(
      () => OdooCustomerRepository(api, session, cache).list(),
      throwsA(isA<AppFailure>()),
    );
  });
  test('phone write requires acknowledgement and server readback', () async {
    var written = false;
    api.handler = (_, method, args, _) async {
      if (method == 'write') {
        written = true;
        expect(args[1], {'phone': '+20 123456789'});
        return true;
      }
      return [
        {'id': 1, 'name': 'Ali', 'phone': '+20 123456789'},
      ];
    };
    await OdooCustomerRepository(
      api,
      session,
      cache,
    ).updatePhone(1, '+20 123456789');
    expect(written, true);
  });
  test('unacknowledged phone write fails', () async {
    api.handler = (_, _, _, _) async => false;
    expect(
      () => OdooCustomerRepository(api, session, cache).updatePhone(1, '12345'),
      throwsA(isA<AppFailure>()),
    );
  });
  test('phone readback cannot use offline cache', () async {
    await cache.save(session.scope, [
      const Customer(id: 1, name: 'Ali', phone: '12345'),
    ]);
    api.handler = (_, method, _, _) async {
      if (method == 'write') {
        return true;
      }
      throw const AppFailure('offline', offline: true);
    };
    expect(
      () => OdooCustomerRepository(api, session, cache).updatePhone(1, '12345'),
      throwsA(isA<AppFailure>()),
    );
  });
  test('restricted account is denied before Sales requests', () async {
    final restricted = Session(session.config, 2, 'portal', 'secret', false);
    api.handler = (_, _, _, _) async => fail('Must not send request');
    expect(
      () => OdooSalesOrderRepository(api, restricted).list(),
      throwsA(isA<AppFailure>()),
    );
  });
  test(
    'confirmation uses action_confirm and verifies resulting server state',
    () async {
      var confirmed = false;
      api.handler = (model, method, args, _) async {
        if (method == 'action_confirm') {
          confirmed = true;
          expect(args, [
            [7],
          ]);
          return true;
        }
        if (model == 'sale.order.line') {
          return [
            {
              'name': 'Homewear',
              'product_uom_qty': 2,
              'price_unit': 100,
              'price_subtotal': 200,
            },
          ];
        }
        return [
          {
            'id': 7,
            'name': 'SO007',
            'partner_id': [3, 'Ali'],
            'state': confirmed ? 'sale' : 'draft',
            'amount_total': 200,
            'currency_id': [1, 'EGP'],
          },
        ];
      };
      final result = await OdooSalesOrderRepository(api, session).confirm(7);
      expect(result.order.state, 'sale');
      expect(result.lines.single.quantity, 2);
    },
  );
  test('permission failure during confirmation is propagated', () async {
    api.handler = (model, method, _, _) async {
      if (method == 'action_confirm') {
        throw const AppFailure('Access denied');
      }
      if (model == 'sale.order.line') {
        return <dynamic>[];
      }
      return [
        {'id': 7, 'name': 'SO007', 'state': 'draft', 'amount_total': 200},
      ];
    };
    expect(
      () => OdooSalesOrderRepository(api, session).confirm(7),
      throwsA(isA<AppFailure>()),
    );
  });
  test('already confirmed orders cannot be confirmed again', () async {
    api.handler = (model, method, _, _) async {
      expect(method, isNot('action_confirm'));
      if (model == 'sale.order.line') {
        return <dynamic>[];
      }
      return [
        {'id': 7, 'name': 'SO007', 'state': 'sale', 'amount_total': 200},
      ];
    };
    expect(
      () => OdooSalesOrderRepository(api, session).confirm(7),
      throwsA(isA<AppFailure>()),
    );
  });
  test('phone validation allows clearing and rejects alphabetic input', () {
    expect(validatePhone(''), isNull);
    expect(validatePhone('+20 (100) 123-4567'), isNull);
    expect(validatePhone('call me'), isNotNull);
  });
}
