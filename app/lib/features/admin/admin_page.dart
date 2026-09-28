import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../auth/auth_widgets.dart';

final managedUsersProvider = FutureProvider<ManagedUsers>((ref) => ref.watch(adminRepositoryProvider).list());

/// Senha aleatória fácil de ditar (sem caracteres parecidos como 0/O, 1/l).
String generatePassword({int length = 10, Random? random}) {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = random ?? Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Página "Administração": criar contas (e-mail e senha), redefinir senha e excluir.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (isAdmin.value != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administração')),
        body: isAdmin.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Apenas o administrador pode acessar esta página.',
              ),
      );
    }
    final users = ref.watch(managedUsersProvider);
    final myEmail = ref.watch(authRepositoryProvider).email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administração'),
        actions: [
          FilledButton.tonalIcon(
            key: const Key('admin-new-user'),
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Novo usuário'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: AsyncView<ManagedUsers>(
        value: users,
        onRetry: () => ref.invalidate(managedUsersProvider),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(managedUsersProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ResponsiveCenter(
                maxWidth: 800,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data.users.length} de ${data.maxUsers} contas',
                              key: const Key('admin-count'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            UsageBar(percent: (data.users.length * 100 / data.maxUsers).round()),
                            const SizedBox(height: 8),
                            Text(
                              'Cada pessoa tem as próprias finanças: ninguém vê os dados de outra conta, '
                              'nem o administrador.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          for (final u in data.users)
                            ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (u.fullName?.isNotEmpty == true ? u.fullName! : u.email).characters.first
                                      .toUpperCase(),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      u.fullName?.isNotEmpty == true ? u.fullName! : u.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (u.isAdmin) ...[
                                    const SizedBox(width: 8),
                                    const Chip(label: Text('Admin'), visualDensity: VisualDensity.compact),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '${u.email}\n${u.lastSignInAt == null ? 'Nunca entrou' : 'Último acesso: ${Dates.format(u.lastSignInAt!)}'}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Ações',
                                onSelected: (v) =>
                                    v == 'password' ? _resetPassword(context, ref, u) : _delete(context, ref, u),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'password', child: Text('Redefinir senha')),
                                  if (u.email != myEmail && !u.isAdmin)
                                    const PopupMenuItem(value: 'delete', child: Text('Excluir conta')),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_NewUser>(context: context, builder: (_) => const _NewUserDialog());
    if (input == null || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).create(name: input.name, email: input.email, password: input.password);
      ref.invalidate(managedUsersProvider);
      if (context.mounted) {
        await _showCredentials(context, title: 'Conta criada', email: input.email, password: input.password);
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, ManagedUser user) async {
    final controller = TextEditingController(text: generatePassword());
    final password = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Redefinir senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Nova senha'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || !context.mounted) return;
    if (password.length < 8) {
      showMessage(context, 'A senha deve ter pelo menos 8 caracteres.', error: true);
      return;
    }
    try {
      await ref.read(adminRepositoryProvider).setPassword(user.id, password);
      if (context.mounted) {
        await _showCredentials(context, title: 'Senha alterada', email: user.email, password: password);
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ManagedUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir conta',
      message:
          'A conta de ${user.email} e TODOS os dados financeiros dela serão apagados. '
          'Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).delete(user.id);
      ref.invalidate(managedUsersProvider);
      if (context.mounted) showMessage(context, 'Conta excluída.');
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _showCredentials(
    BuildContext context, {
    required String title,
    required String email,
    required String password,
  }) {
    final text = 'Acesso ao Meu Financeiro\nE-mail: $email\nSenha: $password';
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Envie estes dados para a pessoa. Ela pode trocar a senha depois em Configurações.'),
            const SizedBox(height: 12),
            SelectableText(text, key: const Key('admin-credentials')),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) showMessage(c, 'Copiado.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Pronto')),
        ],
      ),
    );
  }
}

class _NewUser {
  const _NewUser(this.name, this.email, this.password);
  final String name;
  final String email;
  final String password;
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: generatePassword());

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo usuário'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('new-user-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                validator: AuthValidators.name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-user-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: AuthValidators.email,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-user-password'),
                controller: _password,
                validator: AuthValidators.password,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  helperText: 'A pessoa pode trocar depois.',
                  suffixIcon: IconButton(
                    tooltip: 'Gerar outra senha',
                    onPressed: () => setState(() => _password.text = generatePassword()),
                    icon: const Icon(Icons.autorenew_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('new-user-save'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, _NewUser(_name.text.trim(), _email.text.trim(), _password.text));
          },
          child: const Text('Criar conta'),
        ),
      ],
    );
  }
}
