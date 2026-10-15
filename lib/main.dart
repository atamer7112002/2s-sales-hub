import 'core/sync/phone_sync.dart';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app/app.dart';
import 'core/network/odoo_api.dart';
import 'core/database/customer_cache.dart';
import 'features/authentication/domain/session.dart';
import 'features/authentication/data/auth_repository.dart';
import 'features/authentication/presentation/auth_cubit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final di = GetIt.instance;
  di.registerSingleton<OdooApi>(
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
  final store = SqliteCustomerCache();
  di.registerSingleton<CustomerCache>(store);
  final sync = PhoneSync(di<OdooApi>(), store);
  di.registerSingleton<AuthRepository>(
    SecureAuthRepository(di<OdooApi>(), const FlutterSecureStorage()),
  );
  final auth = AuthCubit(di<AuthRepository>(), di<CustomerCache>());
  runApp(
    SalesHubApp(
      auth: auth,
      api: di<OdooApi>(),
      cache: di<CustomerCache>(),
      sync: sync,
    ),
  );
  auth.restore();
}
