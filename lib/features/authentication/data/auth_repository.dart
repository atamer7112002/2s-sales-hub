import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/odoo_api.dart';
import '../domain/session.dart';

class SecureAuthRepository implements AuthRepository {
  SecureAuthRepository(this.api, this.storage);
  final OdooApi api;
  final FlutterSecureStorage storage;
  @override
  Future<Session> login(
    OdooConfig config,
    String username,
    String password,
  ) async {
    final uid = await api.authenticate(config, username, password);
    final internal =
        await api.execute(config, uid, password, 'res.users', 'has_group', [
          [uid],
          'base.group_user',
        ]) ==
        true;
    await storage.write(
      key: 'session',
      value: jsonEncode({
        'server': config.server,
        'database': config.database,
        'username': username,
        'password': password,
        'uid': uid,
        'internal': internal,
      }),
    );
    return Session(config, uid, username, password, internal);
  }

  @override
  Future<Session?> restore() async {
    final raw = await storage.read(key: 'session');
    if (raw == null) {
      return null;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return await login(
        OdooConfig(data['server'], data['database']),
        data['username'],
        data['password'],
      );
    } on AppFailure catch (e) {
      if (e.offline) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['uid'] is int && data['internal'] is bool) {
          return Session(
            OdooConfig(data['server'], data['database']),
            data['uid'],
            data['username'],
            data['password'],
            data['internal'],
            onlineVerified: false,
          );
        }
      }
      rethrow;
    } catch (_) {
      await logout();
      return null;
    }
  }

  @override
  Future<void> logout() => storage.delete(key: 'session');
}
