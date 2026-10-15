import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/features/authentication/data/auth_repository.dart';

class ApiMock extends Mock implements OdooApi {}

class StorageMock extends Mock implements FlutterSecureStorage {}

void main() {
  late ApiMock api;
  late StorageMock storage;
  late SecureAuthRepository repository;
  final config = OdooConfig('https://example.com', 'demo');
  setUp(() {
    api = ApiMock();
    storage = StorageMock();
    repository = SecureAuthRepository(api, storage);
    when(
      () => storage.write(
        key: 'session',
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: 'session')).thenAnswer((_) async {});
  });
  test(
    'login uses Odoo20 record method for own membership and secure storage',
    () async {
      when(() => api.authenticate(config, 'user', 'secret'))
          .thenAnswer((_) async => 7);
      when(
        () => api.execute(config, 7, 'secret', 'res.users', 'has_group', [
          [7],
          'base.group_user',
        ]),
      ).thenAnswer((_) async => true);
      final result = await repository.login(config, 'user', 'secret');
      expect(result.internal, true);
      expect(result.uid, 7);
      verify(
        () => storage.write(
          key: 'session',
          value: any(named: 'value'),
        ),
      ).called(1);
    },
  );
  test('invalid authentication never saves credentials', () async {
    when(() => api.authenticate(config, 'user', 'wrong'))
        .thenThrow(const AppFailure('Invalid credentials'));
    expect(
      () => repository.login(config, 'user', 'wrong'),
      throwsA(isA<AppFailure>()),
    );
    verifyNever(
      () => storage.write(
        key: 'session',
        value: any(named: 'value'),
      ),
    );
  });
  test('logout clears secure session', () async {
    await repository.logout();
    verify(() => storage.delete(key: 'session')).called(1);
  });
  test(
    'offline restart restores only a previously verified secure session',
    () async {
      when(() => storage.read(key: 'session')).thenAnswer(
        (_) async => jsonEncode({
          'server': 'https://example.com',
          'database': 'demo',
          'username': 'user',
          'password': 'secret',
          'uid': 7,
          'internal': true,
        }),
      );
      // Exact config is created during restore, so match any config.
      registerFallbackValue(config);
      when(() => api.authenticate(any(), 'user', 'secret'))
          .thenThrow(const AppFailure('offline', offline: true));
      final result = await repository.restore();
      expect(result?.uid, 7);
    },
  );
}
