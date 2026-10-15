import '../../../core/sync/phone_sync.dart';
import '../../../core/network/odoo_api.dart';
import '../../../core/database/customer_cache.dart';
import '../../authentication/domain/session.dart';
import '../domain/customer.dart';

class OdooCustomerRepository implements CustomerRepository {
  OdooCustomerRepository(this.api, this.session, this.cache, {this.sync});
  final OdooApi api;
  final Session session;
  final CustomerCache cache;
  final PhoneSync? sync;
  static const fields = [
    'name',
    'phone',
    'city',
    'email',
    'street',
    'street2',
    'state_id',
    'zip',
    'country_id',
  ];
  Future<dynamic> call(
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kw = const {},
  ]) => api.execute(
    session.config,
    session.uid,
    session.password,
    'res.partner',
    method,
    args,
    kw,
  );
  @override
  Future<CustomerPage> list({String query = '', int offset = 0}) async {
    try {
      final rows = await call(
        'search_read',
        [
          [
            ['customer_rank', '>', 0],
            if (query.isNotEmpty) ['name', 'ilike', query],
          ],
        ],
        {
          'fields': fields,
          'limit': 20,
          'offset': offset,
          'order': 'name asc, id asc',
        },
      ) as List;
      final items = rows
          .map((r) => Customer.fromOdoo(Map<String, dynamic>.from(r)))
          .toList();
      await cache.save(session.scope, items);
      final merged = await Future.wait(
        items.map((c) async => await cache.get(session.scope, c.id) ?? c),
      );
      return CustomerPage(merged, hasMore: items.length == 20);
    } on AppFailure catch (e) {
      if (!e.offline) {
        rethrow;
      }
      final items = await cache.read(session.scope, query, offset, 20);
      if (items.isEmpty && offset == 0) {
        rethrow;
      }
      return CustomerPage(items, offline: true, hasMore: items.length == 20);
    }
  }

  @override
  Future<Customer> get(int id, {bool localOnly = false}) async {
    if (localOnly) {
      final c = await cache.get(session.scope, id);
      if (c != null) {
        return c;
      }
      throw const AppFailure('Customer is not saved on this device.');
    }
    return _get(id, allowCache: true);
  }

  Future<Customer> _get(int id, {required bool allowCache}) async {
    try {
      final rows = await call(
        'search_read',
        [
          [
            ['id', '=', id],
            ['customer_rank', '>', 0],
          ],
        ],
        {'fields': fields, 'limit': 1},
      ) as List;
      if (rows.isEmpty) {
        throw const AppFailure(
          'Customer is unavailable or access was removed.',
        );
      }
      final c = Customer.fromOdoo(Map<String, dynamic>.from(rows.first));
      await cache.save(session.scope, [c]);
      return await cache.get(session.scope, id) ?? c;
    } on AppFailure catch (e) {
      if (e.offline && allowCache) {
        final c = await cache.get(session.scope, id);
        if (c != null) {
          return c.cached;
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> updatePhone(int id, String phone) async {
    if (validatePhone(phone) != null) {
      throw AppFailure(validatePhone(phone)!);
    }
    if (sync != null) {
      await sync!.savePhone(session.scope, id, phone.trim());
      return;
    }
    if (await call('write', [
          [id],
          {'phone': phone.trim()},
        ]) !=
        true) {
      throw const AppFailure('Odoo did not acknowledge the update.');
    }
    final fresh = await _get(id, allowCache: false);
    if (fresh.phone != phone.trim()) {
      throw const AppFailure(
        'The server value differs. Refresh and review the phone.',
      );
    }
  }
}
