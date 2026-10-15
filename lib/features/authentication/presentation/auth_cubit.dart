import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/customer_cache.dart';
import '../../../core/network/odoo_api.dart';
import '../domain/session.dart';

class AuthState {
  const AuthState({this.session, this.loading = false, this.error});
  final Session? session;
  final bool loading;
  final String? error;
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this.repository, this.cache)
    : super(const AuthState(loading: true));
  final AuthRepository repository;
  final CustomerCache cache;
  Future<void> Function()? beforeLogout;
  Future<void> restore() async {
    try {
      emit(AuthState(session: await repository.restore()));
    } catch (e) {
      emit(AuthState(error: e.toString()));
    }
  }

  Future<void> login(
    String server,
    String database,
    String username,
    String password,
  ) async {
    emit(const AuthState(loading: true));
    try {
      emit(
        AuthState(
          session: await repository.login(
            OdooConfig(server.trim(), database.trim()),
            username.trim(),
            password,
          ),
        ),
      );
    } catch (e) {
      emit(
        AuthState(
          error: e is AppFailure
              ? e.message
              : 'Secure sign-in failed. Please retry.',
        ),
      );
    }
  }

  Future<void> logout({bool removeLocalData = false}) async {
    final session = state.session;
    try {
      await beforeLogout?.call();
      await repository.logout();
      emit(const AuthState());
      if (session != null) {
        if (!removeLocalData && cache is SqliteCustomerCache) {
          await (cache as SqliteCustomerCache).retainPending(session.scope);
        } else {
          await cache.clear(session.scope);
        }
      }
    } catch (_) {
      emit(
        AuthState(
          error: 'Could not finish local cleanup. Please sign out again.',
          session: state.session,
        ),
      );
    }
  }
}
