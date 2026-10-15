import '../../../app/theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/widgets.dart';
import 'auth_cubit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final server = TextEditingController(
    text: const String.fromEnvironment(
      'ODOO_URL',
      defaultValue: 'https://2s-sales-demo.odoo.com',
    ),
  );
  final database = TextEditingController(
    text: const String.fromEnvironment(
      'ODOO_DB',
      defaultValue: '2s-sales-demo',
    ),
  );
  final username = TextEditingController(), password = TextEditingController();
  bool obscure = true;
  @override
  void dispose() {
    server.dispose();
    database.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      context.read<AuthCubit>().login(
        server.text,
        database.text,
        username.text,
        password.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: BlocBuilder<AuthCubit, AuthState>(
              builder: (context, state) => Form(
                key: form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Brand(),
                      const SizedBox(height: 54),
                      const SectionLabel('Your team workspace'),
                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A little closer to your customers.\nA clearer view of every sale.',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: username,
                        enabled: !state.loading,
                        autofillHints: const [AutofillHints.username],
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Odoo username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter your username'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        enabled: !state.loading,
                        autofillHints: const [AutofillHints.password],
                        obscureText: obscure,
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter your password'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(
                          top: 12,
                          bottom: 4,
                        ),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: const Text(
                          'Connection settings',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                        children: [
                          TextFormField(
                            controller: server,
                            enabled: !state.loading,
                            decoration: const InputDecoration(
                              labelText: 'HTTPS server URL',
                            ),
                            validator: (v) =>
                                v == null || !v.startsWith('https://')
                                ? 'Enter an HTTPS URL'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: database,
                            enabled: !state.loading,
                            decoration: const InputDecoration(
                              labelText: 'Database',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter the database name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: state.loading ? null : submit,
                        child: state.loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Sign in',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'SECURE ACCESS · 2S HOMEWEAR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
