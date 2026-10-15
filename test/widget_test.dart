import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_2s_egypt/features/authentication/domain/session.dart';
import 'package:task_2s_egypt/features/authentication/presentation/auth_cubit.dart';
import 'package:task_2s_egypt/features/authentication/presentation/login_screen.dart';
import 'package:task_2s_egypt/core/database/customer_cache.dart';
import 'package:task_2s_egypt/app/theme.dart';

class AuthMock extends Mock implements AuthRepository {}

class CacheMock extends Mock implements CustomerCache {}

void main() {
  testWidgets('Branded login validates required fields and toggles password', (
    tester,
  ) async {
    final repository = AuthMock();
    when(() => repository.restore()).thenAnswer((_) async => null);
    final cubit = AuthCubit(repository, CacheMock());
    await cubit.restore();
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(theme: salesTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('SALES HUB'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await cubit.close();
  });
}
