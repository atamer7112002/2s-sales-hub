import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_2s_egypt/app/theme.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/authentication/presentation/auth_cubit.dart';
import 'package:task_2s_egypt/features/authentication/presentation/login_screen.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/features/customers/domain/customer.dart';
import 'package:task_2s_egypt/features/customers/presentation/customer_screens.dart';
import 'package:task_2s_egypt/features/sales_orders/domain/sales_order.dart';
import 'package:task_2s_egypt/features/sales_orders/presentation/order_screens.dart';

class ReviewAuth extends Mock implements AuthRepository {}

class ReviewCache extends Mock implements CustomerCache {}

class PreviewCustomers implements CustomerRepository {
  Customer customer = const Customer(
    id: 1,
    name: '2S Demo Customer',
    phone: '01012345678',
    city: 'Cairo',
    email: 'demo.customer@example.com',
    address: 'Cairo, Egypt',
  );
  bool empty = false, error = false, loading = false;
  @override
  Future<CustomerPage> list({String query = '', int offset = 0}) async {
    if (loading) {
      return Completer<CustomerPage>().future;
    }
    if (error) {
      throw const AppFailure('Check your connection and try again.');
    }
    return CustomerPage(empty ? [] : [customer]);
  }

  @override
  Future<Customer> get(int id, {bool localOnly = false}) async => customer;
  @override
  Future<void> updatePhone(int id, String phone) async {
    customer = customer.withSync(phone, 'pending', null);
  }
}

class PreviewOrders implements SalesOrderRepository {
  static const order = SalesOrder(
    id: 1,
    name: 'S00018',
    customer: '2S Demo Customer',
    date: '2026-10-15 10:30:00',
    state: 'draft',
    total: 450,
    currency: 'EGP',
  );
  @override
  Future<List<SalesOrder>> list({int offset = 0, String? status}) async => [
    order,
  ];
  @override
  Future<OrderDetails> get(int id) async => const OrderDetails(order, [
    OrderLine('2S Demo Cotton T-Shirt', 1, 450, 450),
  ]);
  @override
  Future<OrderDetails> confirm(int id) => get(id);
}

void main() {
  setUpAll(() async {
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (font.existsSync()) {
      await (FontLoader('Ahem')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'All redesigned screens render at mobile size without layout errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = ReviewAuth();
      when(() => auth.restore()).thenAnswer(
        (_) async => Session(
          OdooConfig('https://example.com', 'preview'),
          1,
          'Visual review',
          '',
          true,
        ),
      );
      final cubit = AuthCubit(auth, ReviewCache());
      await cubit.restore();
      final customers = PreviewCustomers(), orders = PreviewOrders();
      GlobalKey? screenKey;
      Future<void> screenshot(GlobalKey key, String name) async {
        if (Platform.environment['UPDATE_UI_PREVIEWS'] != '1') return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/screenshots/design-preview')
              .create(recursive: true);
          await File('docs/screenshots/design-preview/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> capture(String name, Widget child) async {
        final key = GlobalKey();
        screenKey = key;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: BlocProvider.value(
              value: cubit,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: salesTheme(),
                home: child,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final scroll in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (axisDirectionToAxis(scroll.axisDirection) == Axis.vertical) {
            scroll.position.jumpTo(0);
          }
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await screenshot(key, name);
      }

      await capture('login', const LoginScreen());
      await capture(
        'customers',
        CustomerListScreen(key: UniqueKey(), repository: customers),
      );
      await capture(
        'customer-details',
        CustomerDetailScreen(key: UniqueKey(), repository: customers, id: 1),
      );
      await tester.ensureVisible(find.text('Edit phone'));
      await tester.tap(find.text('Edit phone'));
      await tester.pumpAndSettle();
      expect(find.text('Leave blank to remove the phone.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(screenKey!, 'edit-phone');
      await capture(
        'sales-orders',
        OrderListScreen(key: UniqueKey(), repository: orders),
      );
      await capture(
        'order-details',
        OrderDetailScreen(key: UniqueKey(), repository: orders, id: 1),
      );
      customers.customer = customers.customer
          .withSync('01099998888', 'pending', null)
          .cached;
      await capture(
        'offline-pending',
        CustomerDetailScreen(key: UniqueKey(), repository: customers, id: 1),
      );
      customers.customer = customers.customer.withSync(
        '01099998888',
        'failed',
        'Your phone edit is safe. Check your account permissions and retry.',
      );
      await capture(
        'sync-failed',
        CustomerDetailScreen(key: UniqueKey(), repository: customers, id: 1),
      );
      customers.empty = true;
      await capture(
        'empty',
        CustomerListScreen(key: UniqueKey(), repository: customers),
      );
      customers.error = true;
      await capture(
        'error',
        CustomerListScreen(key: UniqueKey(), repository: customers),
      );
      customers.error = false;
      customers.loading = true;
      await capture(
        'loading',
        CustomerListScreen(key: UniqueKey(), repository: customers),
      );
      await tester.pumpWidget(const SizedBox());
      await cubit.close();
    },
  );
}
