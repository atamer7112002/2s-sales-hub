import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/sync/phone_sync.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/database/customer_cache.dart';
import '../core/network/odoo_api.dart';
import '../features/authentication/presentation/auth_cubit.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/customers/data/customer_repository.dart';
import '../features/customers/presentation/customer_screens.dart';
import '../features/sales_orders/data/sales_order_repository.dart';
import '../features/sales_orders/presentation/order_screens.dart';
import 'theme.dart';

class AuthRefresh extends ChangeNotifier {
  AuthRefresh(AuthCubit auth) {
    subscription = auth.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription subscription;
  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

class SalesHubApp extends StatefulWidget {
  const SalesHubApp({
    super.key,
    required this.auth,
    required this.api,
    required this.cache,
    required this.sync,
  });
  final AuthCubit auth;
  final OdooApi api;
  final CustomerCache cache;
  final PhoneSync sync;
  @override
  State<SalesHubApp> createState() => _SalesHubAppState();
}

class _SalesHubAppState extends State<SalesHubApp> with WidgetsBindingObserver {
  StreamSubscription? _authSubscription, _networkSubscription;
  Timer? _syncTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.beforeLogout = () => widget.sync.setSession(null);
    _authSubscription = widget.auth.stream.listen((state) {
      if (!identical(state.session, widget.sync.session)) {
        unawaited(widget.sync.setSession(state.session));
      }
    });
    _networkSubscription = Connectivity().onConnectivityChanged.listen(
      (results) => widget.sync.connectionChanged(
        !results.contains(ConnectivityResult.none),
      ),
    );
    _syncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(widget.sync.synchronize()),
    );
    if (widget.auth.state.session != null) {
      unawaited(widget.sync.setSession(widget.auth.state.session));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.sync.synchronize());
    }
  }

  late final refresh = AuthRefresh(widget.auth);
  OdooCustomerRepository get customers => OdooCustomerRepository(
    widget.api,
    widget.auth.state.session!,
    widget.cache,
    sync: widget.sync,
  );
  OdooSalesOrderRepository get orders =>
      OdooSalesOrderRepository(widget.api, widget.auth.state.session!);
  late final router = GoRouter(
    initialLocation: '/customers',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = widget.auth.state.session;
      if (session == null) {
        return state.matchedLocation == '/login' ? null : '/login';
      }
      if (state.matchedLocation == '/login') {
        return '/customers';
      }
      if (state.matchedLocation.startsWith('/orders') && !session.internal) {
        return '/customers';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/customers',
        builder: (_, _) => CustomerListScreen(
          key: ValueKey(widget.auth.state.session!.scope),
          repository: customers,
          sync: widget.sync,
        ),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => CustomerDetailScreen(
              repository: customers,
              sync: widget.sync,
              key: ValueKey(
                '${widget.auth.state.session!.scope}:${s.pathParameters["id"]}',
              ),
              id: int.tryParse(s.pathParameters['id']!) ?? 0,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/orders',
        builder: (_, _) => OrderListScreen(
          key: ValueKey(widget.auth.state.session!.scope),
          repository: orders,
        ),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => OrderDetailScreen(
              key: ValueKey(
                '${widget.auth.state.session!.scope}:${s.pathParameters["id"]}',
              ),
              repository: orders,
              id: int.tryParse(s.pathParameters['id']!) ?? 0,
            ),
          ),
        ],
      ),
    ],
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _networkSubscription?.cancel();
    _syncTimer?.cancel();
    widget.auth.beforeLogout = null;
    router.dispose();
    refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: widget.auth,
    child: MaterialApp.router(
      title: '2S Sales Hub',
      debugShowCheckedModeBanner: false,
      theme: salesTheme(),
      routerConfig: router,
    ),
  );
}

class HubScaffold extends StatelessWidget {
  const HubScaffold({
    super.key,
    required this.title,
    required this.child,
    this.orders = false,
  });
  final String title;
  final Widget child;
  final bool orders;
  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthCubit>();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 86,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2S HOMEWEAR',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 10,
                letterSpacing: 2.6,
                color: goldInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 25,
                letterSpacing: -.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Account and sign out',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (sheet) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        auth.state.session?.username ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('2S Homewear · Odoo workspace'),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheet);
                          auth.logout();
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Signing out keeps unsynced edits for this account. Sign in again to resume.',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: sheet,
                            builder: (dialog) => AlertDialog(
                              title: const Text('Discard local account data?'),
                              content: const Text(
                                'This permanently removes cached customers and all unsynced phone edits for this account on this device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: const Text('Discard and sign out'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && sheet.mounted) {
                            Navigator.pop(sheet);
                            await auth.logout(removeLocalData: true);
                          }
                        },
                        child: const Text('Remove local data and sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: !(auth.state.session?.internal ?? false)
          ? null
          : NavigationBar(
              selectedIndex: orders ? 1 : 0,
              onDestinationSelected: (i) =>
                  context.go(i == 0 ? '/customers' : '/orders'),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: 'Customers',
                ),
                if (auth.state.session?.internal ?? false)
                  const NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'Sales orders',
                  ),
              ],
            ),
    );
  }
}
