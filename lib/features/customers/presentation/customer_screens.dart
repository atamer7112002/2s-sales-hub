import '../../../app/theme.dart';
import '../../../core/sync/phone_sync.dart';
import '../../../core/sync/sync_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app.dart';
import '../../../app/widgets.dart';
import '../../../core/network/paged_cubit.dart';
import '../domain/customer.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key, required this.repository, this.sync});
  final PhoneSync? sync;
  final CustomerRepository repository;
  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  late final cubit = PagedCubit<Customer>((query, offset) async {
    final p = await widget.repository.list(query: query, offset: offset);
    return PageResult(p.items, p.hasMore, offline: p.offline);
  })..load();
  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(refreshLocal);
  }

  Future<void> refreshLocal() async {
    if (cubit.state.loading) {
      return;
    }
    final items = cubit.state.items;
    try {
      final fresh = await Future.wait(
        items.map((c) => widget.repository.get(c.id, localOnly: true)),
      );
      if (mounted && identical(items, cubit.state.items)) {
        cubit.replaceItems(fresh);
      }
    } catch (_) {
      /* Keep visible data if local storage is temporarily unavailable. */
    }
  }

  @override
  void dispose() {
    widget.sync?.removeListener(refreshLocal);
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HubScaffold(
    title: 'Customers',
    child: Column(
      children: [
        if (widget.sync != null) SyncBar(widget.sync!),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR CUSTOMER RELATIONSHIPS',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                onChanged: cubit.search,
                decoration: const InputDecoration(
                  hintText: 'Search customer name',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: BlocBuilder<PagedCubit<Customer>, PageState<Customer>>(
            bloc: cubit,
            builder: (context, state) => RefreshIndicator(
              onRefresh: () => cubit.load(reset: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (state.offline)
                    const MaterialBanner(
                      content: Text(
                        'Offline · showing saved customers. Phone edits will sync when connected.',
                      ),
                      actions: [SizedBox.shrink()],
                    ),
                  if (state.loading && state.items.isEmpty) const LoadingRows(),
                  if (!state.loading &&
                      state.items.isEmpty &&
                      state.error == null)
                    const EmptyNotice(
                      title: 'No customers found',
                      message: 'Try a different name or pull down to refresh.',
                      icon: Icons.people_outline,
                    ),
                  for (final c in state.items)
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: goldWash,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              color: goldInk,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  c.phone.isEmpty ? 'No phone' : c.phone,
                                  c.city,
                                ].where((v) => v.isNotEmpty).join(' · '),
                                style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              CustomerSyncStatus(c),
                            ],
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: muted,
                        ),
                        onTap: () async {
                          await context.push('/customers/${c.id}');
                          if (mounted) {
                            if (widget.sync?.offline ?? false) {
                              refreshLocal();
                            } else {
                              cubit.load(reset: true);
                            }
                          }
                        },
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

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.repository,
    required this.id,
    this.sync,
  });
  final PhoneSync? sync;
  final CustomerRepository repository;
  final int id;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<Customer> future = widget.repository.get(widget.id);
  final phone = TextEditingController();
  final form = GlobalKey<FormState>();
  bool saving = false;
  Customer? shown;
  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(refreshLocal);
  }

  Future<void> refreshLocal() async {
    if (shown == null) {
      return;
    }
    try {
      final local = await widget.repository.get(widget.id, localOnly: true);
      if (mounted) {
        setState(() => future = Future.value(local));
      }
    } catch (_) {
      /* Keep the current profile if storage is unavailable. */
    }
  }

  void reload() => setState(() => future = widget.repository.get(widget.id));
  @override
  void dispose() {
    widget.sync?.removeListener(refreshLocal);
    phone.dispose();
    super.dispose();
  }

  Future<void> edit(Customer c) async {
    phone.text = c.phone;
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit phone'),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        content: Form(
          key: form,
          child: TextFormField(
            controller: phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              helperText: 'Leave blank to remove the phone.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (v) => validatePhone(v ?? ''),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialog, phone.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) {
      return;
    }
    setState(() => saving = true);
    try {
      await widget.repository.updatePhone(c.id, value);
      if (mounted) {
        feedback(
          context,
          widget.sync == null
              ? 'Phone saved in Odoo'
              : (widget.sync!.offline
                    ? 'Phone number saved offline. It will sync automatically when you’re back online.'
                    : 'Phone number saved on this device. Syncing with Odoo.'),
        );
        if (widget.sync != null) {
          await refreshLocal();
        } else {
          reload();
        }
      }
    } catch (e) {
      if (mounted) {
        feedback(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer details')),
    body: FutureBuilder<Customer>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorNotice(snapshot.error.toString(), reload);
        }
        final c = snapshot.data;
        if (c == null) {
          return const LoadingRows();
        }
        shown = c;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            if (widget.sync != null) SyncBar(widget.sync!),
            if (c.offline)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: StatusPill('Offline · saved profile', tone: 'grey'),
              ),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Customer profile'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: goldWash,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          c.name.isEmpty ? '?' : c.name[0],
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 25,
                            color: goldInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            if (c.city.isNotEmpty)
                              Text(
                                c.city,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 8),
                            CustomerSyncStatus(c),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (c.syncError != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  c.syncError!,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 28),
            const SectionLabel('Contact information'),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.phone_outlined,
                      size: 21,
                      color: goldInk,
                    ),
                    title: Text(
                      'Phone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    subtitle: Text(
                      c.phone.isEmpty ? 'Not provided' : c.phone,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 15,
                        color: ink,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Copy phone',
                      icon: const Icon(Icons.copy_outlined, size: 19),
                      onPressed: c.phone.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: c.phone));
                              feedback(context, 'Phone copied');
                            },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.mail_outline,
                      size: 21,
                      color: goldInk,
                    ),
                    title: Text(
                      'Email',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    subtitle: Text(
                      c.email.isEmpty ? 'Not provided' : c.email,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 14,
                        color: ink,
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      size: 21,
                      color: goldInk,
                    ),
                    title: Text(
                      'Address',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    subtitle: Text(
                      c.address.isEmpty ? 'Not provided' : c.address,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 14,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (c.phone.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Call'),
                      onPressed: () async {
                        try {
                          final ok = await launchUrl(
                            Uri(scheme: 'tel', path: c.phone),
                          );
                          if (!ok && context.mounted) {
                            feedback(context, 'No calling app is available.');
                          }
                        } catch (_) {
                          if (context.mounted) {
                            feedback(
                              context,
                              'Unable to open the calling app.',
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: saving ? null : () => edit(c),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined, size: 18),
                    label: Text(saving ? 'Saving…' : 'Edit phone'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Changes sync when you’re connected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: muted,
              ),
            ),
          ],
        );
      },
    ),
  );
}
