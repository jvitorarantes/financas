import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failure.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_widgets.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = toFailure(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        title: 'Verifique seu e-mail',
        subtitle: 'Se existir uma conta com esse e-mail, você receberá um link para criar uma nova senha.',
        child: FilledButton(onPressed: () => context.go('/login'), child: const Text('Voltar para o login')),
      );
    }
    return AuthScaffold(
      title: 'Recuperar senha',
      subtitle: 'Informe o e-mail da sua conta e enviaremos um link para redefinir a senha.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: AuthValidators.email,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline_rounded)),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton(onPressed: _loading ? null : _submit, child: const Text('Enviar link')),
            TextButton(onPressed: () => context.go('/login'), child: const Text('Voltar')),
          ],
        ),
      ),
    );
  }
}

/// Aberta pelo link de recuperação (evento passwordRecovery do Supabase).
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      showMessage(context, 'Senha alterada com sucesso.');
      context.go('/');
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Nova senha',
      subtitle: 'Escolha uma nova senha para sua conta.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(controller: _password, label: 'Nova senha'),
            const SizedBox(height: 14),
            PasswordField(
              controller: _confirm,
              label: 'Confirmar nova senha',
              validator: (v) => v != _password.text ? 'As senhas não conferem.' : null,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _loading ? null : _submit, child: const Text('Salvar nova senha')),
          ],
        ),
      ),
    );
  }
}
