import '../../app/widgets.dart';
import '../../app/theme.dart';

import 'package:flutter/material.dart';

import 'phone_sync.dart';
import '../../features/customers/domain/customer.dart';

String syncLabel(String status) =>
    {
      'pending': 'Pending Sync',
      'syncing': 'Syncing',
      'synced': 'Synced',
      'failed': 'Sync Failed',
    }[status] ??
    'Pending Sync';

class CustomerSyncStatus extends StatelessWidget {
  const CustomerSyncStatus(this.customer, {super.key});
  final Customer customer;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    child: StatusPill(
      syncLabel(customer.syncStatus),
      key: ValueKey(customer.syncStatus),
      tone: customer.syncStatus == 'failed'
          ? 'red'
          : customer.syncStatus == 'synced'
          ? 'green'
          : 'gold',
    ),
  );
}

class SyncBar extends StatelessWidget {
  const SyncBar(this.sync, {super.key});
  final PhoneSync sync;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sync.offline
                    ? Icons.cloud_off_outlined
                    : sync.busy
                    ? Icons.sync
                    : Icons.cloud_done_outlined,
                size: 14,
                color: muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sync.offline
                      ? 'Offline · edits are saved on this device'
                      : sync.busy
                      ? 'Syncing saved edits…'
                      : sync.outstanding > 0
                      ? '${sync.outstanding} saved edit(s) awaiting sync'
                      : 'Synced',
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 11,
                    color: muted,
                  ),
                ),
              ),
              if (sync.outstanding > 0)
                TextButton(
                  onPressed: sync.busy
                      ? null
                      : () async {
                          final s = sync.session;
                          if (s == null) {
                            return;
                          }
                          final conflicts =
                              (await sync.store.operations(s.scope)).any(
                                (op) =>
                                    op.kind == 'conflict' &&
                                    op.status == 'failed',
                              );
                          if (!context.mounted) {
                            return;
                          }
                          bool override = false;
                          if (conflicts) {
                            override =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    title: const Text('Review phone conflicts'),
                                    content: const Text(
                                      'A phone number changed in Odoo. Retrying will apply your saved phone and overwrite the current Odoo value. Check the customer in Odoo first.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialog, true),
                                        child: const Text(
                                          'Apply my saved phone',
                                        ),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!override) {
                              return;
                            }
                          }
                          await sync.retry(
                            overrideConflicts: override,
                            scope: s.scope,
                          );
                        },
                  child: const Text('Retry Sync'),
                ),
            ],
          ),
          if (sync.error != null && sync.outstanding > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                sync.error!,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
