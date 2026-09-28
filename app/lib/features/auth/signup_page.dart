import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failure.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_widgets.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _checkEmail = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final needsConfirmation = await ref
          .read(authRepositoryProvider)
          .signUp(name: _name.text, email: _email.text, password: _password.text);
      if (mounted && needsConfirmation) setState(() => _checkEmail = true);
    } catch (e) {
      if (mounted) setState(() => _error = toFailure(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkEmail) {
      return AuthScaffold(
        title: 'Confirme seu e-mail',
        subtitle: 'Enviamos um link para ${_email.text.trim()}. Abra o link para ativar sua conta e depois entre.',
        child: FilledButton(onPressed: () => context.go('/login'), child: const Text('Ir para o login')),
      );
    }
    return AuthScaffold(
      title: 'Criar conta',
      subtitle:
          'No primeiro acesso, esta será a conta de administrador. Com ela você cria o acesso das outras pessoas.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('signup-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.name,
                decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline_rounded)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('signup-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
              const SizedBox(height: 14),
              PasswordField(controller: _password),
              const SizedBox(height: 14),
              PasswordField(
                controller: _confirm,
                label: 'Confirmar senha',
                validator: (v) => v != _password.text ? 'As senhas não conferem.' : null,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              FilledButton(
                key: const Key('signup-submit'),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Criar conta'),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Já tem conta?'),
                  TextButton(onPressed: () => context.go('/login'), child: const Text('Entrar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
