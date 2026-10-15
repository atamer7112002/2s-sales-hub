import '../../../core/network/odoo_api.dart';
import '../../authentication/domain/session.dart';
import '../domain/sales_order.dart';

class OdooSalesOrderRepository implements SalesOrderRepository {
  OdooSalesOrderRepository(this.api, this.session);
  final OdooApi api;
  final Session session;
  static const fields = [
    'name',
    'partner_id',
    'date_order',
    'state',
    'amount_total',
    'currency_id',
  ];
  Future<dynamic> call(
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kw = const {},
  ]) {
    if (!session.internal) {
      throw const AppFailure('Sales orders require an internal Odoo account.');
    }
    return api.execute(
      session.config,
      session.uid,
      session.password,
      model,
      method,
      args,
      kw,
    );
  }

  @override
  Future<List<SalesOrder>> list({int offset = 0, String? status}) async {
    final rows = await call(
      'sale.order',
      'search_read',
      [
        [
          if (status != null) ['state', '=', status],
        ],
      ],
      {
        'fields': fields,
        'offset': offset,
        'limit': 20,
        'order': 'date_order desc, id desc',
      },
    ) as List;
    return rows
        .map((r) => SalesOrder.fromOdoo(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<OrderDetails> get(int id) async {
    final rows = await call(
      'sale.order',
      'read',
      [
        [id],
      ],
      {'fields': fields},
    ) as List;
    if (rows.isEmpty) {
      throw const AppFailure('Order is no longer available.');
    }
    final order = SalesOrder.fromOdoo(Map<String, dynamic>.from(rows.first));
    final lines = await call(
      'sale.order.line',
      'search_read',
      [
        [
          ['order_id', '=', id],
          ['display_type', '=', false],
        ],
      ],
      {
        'fields': ['name', 'product_uom_qty', 'price_unit', 'price_subtotal'],
        'order': 'sequence, id',
      },
    ) as List;
    return OrderDetails(
      order,
      lines
          .map((r) => OrderLine.fromOdoo(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }

  @override
  Future<OrderDetails> confirm(int id) async {
    final current = await get(id);
    if (!current.order.canConfirm) {
      throw const AppFailure('This order is no longer an eligible quotation.');
    }
    await call('sale.order', 'action_confirm', [
      [id],
    ]);
    final result = await get(id);
    if (!{'sale', 'done'}.contains(result.order.state)) {
      throw const AppFailure(
        'Confirmation is not complete. Refresh the order in Odoo.',
      );
    }
    return result;
  }
}
