// Opt-in real backend verification. Credentials arrive through a private socket.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/core/sync/phone_sync.dart';
import 'package:task_2s_egypt/features/authentication/data/auth_repository.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/customers/data/customer_repository.dart';
import 'package:task_2s_egypt/features/sales_orders/data/sales_order_repository.dart';

import 'live_offline_check.dart' show OfflineGate;

void main() {
  test(
    'reviewer app authentication, customers, Sales and offline synchronization',
    () async {
      final setup = jsonDecode(
        await File('docs/reviewer_setup.json').readAsString(),
      ) as Map<String, dynamic>;
      final report = <String, dynamic>{
        'status': 'in_progress',
        'checked_at_utc': DateTime.now().toUtc().toIso8601String(),
        'reviewer_login': setup['reviewer_login'],
      };
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
      Directory? temp;
      SqliteCustomerCache? store;
      PhoneSync? sync;
      Session? session;
      String? original;
      bool touched = false;
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
        final socket = await Socket.connect(
          InternetAddress(
            Platform.environment['TWO_S_CREDENTIAL_SOCKET']!,
            type: InternetAddressType.unix,
          ),
          0,
        );
        final raw = await socket.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        await socket.close();
        final credentials = jsonDecode(utf8.decode(raw));
        // This opt-in Flutter test lives outside test/ to avoid live API calls in normal tests.
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterSecureStorage.setMockInitialValues(
          {},
        ); // Only OS-storage plugin replaced for desktop test; backend is real.
        final auth = SecureAuthRepository(api, const FlutterSecureStorage());
        stage = 'actual app authentication repository';
        session = await auth.login(
          OdooConfig('https://2s-sales-demo.odoo.com', '2s-sales-demo'),
          credentials['login'],
          credentials['password'],
        );
        if (!session.internal) {
          throw StateError('Not internal');
        }
        if (await call('res.users', 'has_group', [
              [session.uid],
              'base.group_system',
            ]) ==
            true) {
          throw StateError('Unexpected administrator');
        }
        report['app_xmlrpc_login'] = 'passed';
        report['internal_non_admin'] = 'passed';
        sqfliteFfiInit();
        temp = await Directory.systemTemp.createTemp('2s-reviewer-');
        final path = '${temp.path}/cache.db';
        store = SqliteCustomerCache(path: path, factory: databaseFactoryFfi);
        sync = PhoneSync(api, store);
        await sync.setSession(session);
        await sync.synchronize();
        var customers = OdooCustomerRepository(api, session, store, sync: sync);
        stage = 'customer name search';
        final page = await customers.list(query: '2S Demo Customer');
        if (!page.items.any((c) => c.id == setup['customer_id'])) {
          throw StateError('Synthetic customer not visible');
        }
        final customer = await customers.get(setup['customer_id']);
        if (customer.email != 'demo.customer@example.com') {
          throw StateError('Synthetic record identity mismatch');
        }
        original = customer.phone;
        report['customer_search_details'] = 'passed';
        final orders = OdooSalesOrderRepository(api, session);
        stage = 'Sales list/details';
        if (!(await orders.list()).any((o) => o.id == setup['quotation_id'])) {
          throw StateError('Main quotation unavailable');
        }
        final details = await orders.get(setup['quotation_id']);
        if (details.order.state != 'draft' ||
            details.order.total != 450 ||
            details.lines.single.quantity != 1) {
          throw StateError('Review quotation validation failed');
        }
        report['sales_list_and_details'] = 'passed';
        stage = 'offline phone edit and restart';
        api.offline = true;
        sync.connectionChanged(false);
        await customers.updatePhone(customer.id, '01000001111');
        touched = true;
        await sync.synchronize();
        if ((await store.operations(session.scope)).single.status !=
            'pending') {
          throw StateError('Queue missing');
        }
        await sync.setSession(null);
        sync.dispose();
        await store.close();
        store = SqliteCustomerCache(path: path, factory: databaseFactoryFfi);
        sync = PhoneSync(api, store);
        await sync.setSession(session);
        await sync.synchronize();
        if ((await store.get(session.scope, customer.id))!.phone !=
            '01000001111') {
          throw StateError('Restart lost edit');
        }
        report['offline_edit_sqlite_restart'] = 'passed';
        stage = 'reconnect and verify real Odoo';
        api.offline = false;
        sync.connectionChanged(true);
        await sync.synchronize();
        if ((await store.operations(session.scope)).single.status != 'synced') {
          throw StateError('Sync failed');
        }
        final rows = await call(
          'res.partner',
          'read',
          [
            [customer.id],
          ],
          {
            'fields': ['phone'],
          },
        ) as List;
        if (rows.single['phone'] != '01000001111') {
          throw StateError('Readback mismatch');
        }
        report['verified_phone_write_and_sync'] = 'passed';
        stage = 'restore demo phone';
        customers = OdooCustomerRepository(api, session, store, sync: sync);
        await customers.updatePhone(customer.id, original);
        await sync.synchronize();
        if ((await call(
              'res.partner',
              'read',
              [
                [customer.id],
              ],
              {
                'fields': ['phone'],
              },
            ) as List).single['phone'] !=
            original) {
          throw StateError('Restoration mismatch');
        }
        touched = false;
        report['demo_phone_restored'] = 'passed';
        if ((await orders.get(setup['quotation_id'])).order.state != 'draft') {
          throw StateError('Main quotation state changed');
        }
        report['main_quotation_remains_draft'] = true;
        report['status'] = 'passed';
        await auth.logout();
      } catch (e) {
        report['status'] = 'failed';
        report['failure_stage'] = stage;
        report['failure_type'] = e.runtimeType.toString();
      } finally {
        if (sync != null) {
          await sync.setSession(null);
          sync.dispose();
        }
        api.offline = false;
        if (touched && original != null && session != null) {
          try {
            await call('res.partner', 'write', [
              [setup['customer_id']],
              {'phone': original},
            ]);
            report['demo_phone_restored'] = 'passed';
          } catch (_) {
            report['demo_phone_restored'] = 'failed';
          }
        }
        if (store != null) {
          await store.close();
        }
        if (temp != null) {
          await temp.delete(recursive: true);
        }
        await File('docs/reviewer_app_verification.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      }
      expect(
        report['status'],
        'passed',
        reason: 'See sanitized reviewer_app_verification.json. No credentials/raw RPC faults logged.',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
