import '../../../core/network/odoo_api.dart';

class Session {
  const Session(
    this.config,
    this.uid,
    this.username,
    this.password,
    this.internal, {
    this.onlineVerified = true,
  });
  final OdooConfig config;
  final int uid;
  final String username, password;
  final bool internal;
  final bool onlineVerified;
  String get scope => '${config.server}|${config.database}|$uid';
}

abstract interface class AuthRepository {
  Future<Session> login(OdooConfig config, String username, String password);
  Future<Session?> restore();
  Future<void> logout();
}
