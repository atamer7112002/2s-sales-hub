import '../../../app/theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/widgets.dart';
import '../../../core/network/paged_cubit.dart';
import '../domain/sales_order.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key, required this.repository});
  final SalesOrderRepository repository;
  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  late final cubit = PagedCubit<SalesOrder>((status, offset) async {
    final rows = await widget.repository.list(
      offset: offset,
      status: status.isEmpty ? null : status,
    );
    return PageResult(rows, rows.length == 20);
  })..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HubScaffold(
    title: 'Sales orders',
    orders: true,
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              for (final entry in {
                '': 'All',
                'draft': 'Quotation',
                'sent': 'Sent',
                'sale': 'Confirmed',
                'cancel': 'Cancelled',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: cubit.query == entry.key,
                    onSelected: (_) {
                      setState(() => cubit.query = entry.key);
                      cubit.load(reset: true);
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: BlocBuilder<PagedCubit<SalesOrder>, PageState<SalesOrder>>(
            bloc: cubit,
            builder: (context, state) => RefreshIndicator(
              onRefresh: () => cubit.load(reset: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (state.loading && state.items.isEmpty) const LoadingRows(),
                  if (!state.loading &&
                      state.error == null &&
                      state.items.isEmpty)
                    const EmptyNotice(
                      title: 'No orders in this view',
                      message: 'Choose another status or pull down to refresh.',
                      icon: Icons.receipt_long_outlined,
                    ),
                  for (final o in state.items)
                    SurfaceCard(
                      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await context.push('/orders/${o.id}');
                          if (mounted) {
                            cubit.load(reset: true);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  StatusPill(
                                    statusLabel(o.state),
                                    tone: orderTone(o.state),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                o.customer,
                                style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 14,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Divider(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.date.split(' ').first,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  Text(
                                    '${o.total.toStringAsFixed(2)} ${o.currency}',
                                    style: const TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.3,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 17,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (state.error != null)
                    ErrorNotice(
                      state.error!,
                      () => cubit.load(reset: state.items.isEmpty),
                    ),
                  if (state.hasMore &&
                      state.items.isNotEmpty &&
                      state.error == null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: OutlinedButton(
                        onPressed: state.loading ? null : () => cubit.load(),
                        child: Text(state.loading ? 'Loading…' : 'Load more'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

String orderTone(String state) => {'sale', 'done'}.contains(state)
    ? 'green'
    : state == 'cancel'
    ? 'grey'
    : 'gold';

String statusLabel(String state) =>
    {
      'draft': 'Quotation',
      'sent': 'Quotation sent',
      'sale': 'Confirmed',
      'done': 'Completed',
      'cancel': 'Cancelled',
    }[state] ??
    state;

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.repository,
    required this.id,
  });
  final SalesOrderRepository repository;
  final int id;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<OrderDetails> future = widget.repository.get(widget.id);
  bool confirming = false;
  void reload() => setState(() => future = widget.repository.get(widget.id));
  Future<void> confirm() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Confirm this quotation?'),
        content: const Text(
          'This creates a confirmed sales order in Odoo. Review the customer, products and total before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm order'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }
    setState(() => confirming = true);
    try {
      final result = await widget.repository.confirm(widget.id);
      if (mounted) {
        setState(() => future = Future.value(result));
        feedback(context, 'Order confirmed in Odoo');
      }
    } catch (e) {
      if (mounted) {
        feedback(context, e.toString());
        reload();
      }
    } finally {
      if (mounted) {
        setState(() => confirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Order details'),
      actions: [
        IconButton(
          tooltip: 'Refresh order',
          onPressed: confirming ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<OrderDetails>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorNotice(snapshot.error.toString(), reload);
        }
        final details = snapshot.data;
        if (details == null) {
          return const LoadingRows();
        }
        final o = details.order;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Sales order'),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      StatusPill(
                        statusLabel(o.state),
                        tone: orderTone(o.state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 18),
                  Text(
                    o.customer,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: muted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '${o.date} UTC',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionLabel('Products & quantities'),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (details.lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No product lines.'),
                    ),
                  for (var i = 0; i < details.lines.length; i++) ...[
                    if (i > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            details.lines[i].name,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${details.lines[i].quantity} × ${details.lines[i].unitPrice.toStringAsFixed(2)} ${o.currency}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                details.lines[i].subtotal.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order total',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Including taxes',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 11,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${o.total.toStringAsFixed(2)} ${o.currency}',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (o.canConfirm)
              FilledButton.icon(
                onPressed: confirming ? null : confirm,
                icon: const Icon(Icons.check_circle_outline, size: 19),
                label: Text(
                  confirming ? 'Confirming in Odoo…' : 'Confirm quotation',
                ),
              ),
            if (o.canConfirm)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Review the order before confirming.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 11,
                    color: muted,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
