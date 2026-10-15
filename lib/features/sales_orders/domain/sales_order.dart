import '../../customers/domain/customer.dart';

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.name,
    required this.customer,
    required this.date,
    required this.state,
    required this.total,
    required this.currency,
  });
  final int id;
  final String name, customer, date, state, currency;
  final double total;
  bool get canConfirm => state == 'draft' || state == 'sent';
  factory SalesOrder.fromOdoo(Map<String, dynamic> r) => SalesOrder(
    id: r['id'],
    name: odooText(r['name']),
    customer: relationName(r['partner_id']),
    date: odooText(r['date_order']),
    state: odooText(r['state']),
    total: (r['amount_total'] as num).toDouble(),
    currency: relationName(r['currency_id']),
  );
}

class OrderLine {
  const OrderLine(this.name, this.quantity, this.unitPrice, this.subtotal);
  final String name;
  final double quantity, unitPrice, subtotal;
  factory OrderLine.fromOdoo(Map<String, dynamic> r) => OrderLine(
    odooText(r['name']),
    (r['product_uom_qty'] as num).toDouble(),
    (r['price_unit'] as num).toDouble(),
    (r['price_subtotal'] as num).toDouble(),
  );
}

class OrderDetails {
  const OrderDetails(this.order, this.lines);
  final SalesOrder order;
  final List<OrderLine> lines;
}

abstract interface class SalesOrderRepository {
  Future<List<SalesOrder>> list({int offset = 0, String? status});
  Future<OrderDetails> get(int id);
  Future<OrderDetails> confirm(int id);
}
