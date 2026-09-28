import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/models/account.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';

final profileNameProvider = FutureProvider<String?>((ref) => ref.watch(catalogRepositoryProvider).profileName());

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authRepositoryProvider);
    final name = ref.watch(profileNameProvider).value;
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          ResponsiveCenter(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: 'Perfil',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                    title: Text(name?.isNotEmpty == true ? name! : 'Sem nome'),
                    subtitle: Text(auth.email ?? ''),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final value = await _askText(context, title: 'Seu nome', initial: name ?? '');
                      if (value == null || value.trim().isEmpty) return;
                      try {
                        await ref.read(catalogRepositoryProvider).updateProfileName(value);
                        ref.invalidate(profileNameProvider);
                      } catch (e) {
                        if (context.mounted) showFailure(context, e);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Contas',
                  action: TextButton.icon(
                    onPressed: () => _editAccount(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova'),
                  ),
                  child: AsyncView<List<Account>>(
                    value: accounts,
                    onRetry: () => ref.invalidate(accountsProvider),
                    data: (list) => Column(
                      children: [
                        for (final a in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(a.archived ? Icons.archive_outlined : Icons.account_balance_rounded),
                            title: Text(
                              a.name,
                              style: TextStyle(decoration: a.archived ? TextDecoration.lineThrough : null),
                            ),
                            subtitle: Text('${a.type.label}${a.includeInBalance ? '' : ' · fora do saldo'}'),
                            trailing: MoneyText(
                              a.balanceCents,
                              colored: true,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onTap: () => _editAccount(context, ref, a),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Categorias',
                  action: TextButton.icon(
                    onPressed: () => _editCategory(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova'),
                  ),
                  child: AsyncView<List<Category>>(
                    value: categories,
                    onRetry: () => ref.invalidate(categoriesProvider),
                    data: (list) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final kind in CategoryKind.values) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              kind == CategoryKind.expense ? 'Despesas' : 'Receitas',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in list.where((c) => c.kind == kind))
                                InputChip(
                                  avatar: Icon(iconFor(c.icon), size: 18, color: colorFromHex(c.color)),
                                  label: Text(
                                    c.name,
                                    style: TextStyle(decoration: c.archived ? TextDecoration.lineThrough : null),
                                  ),
                                  onPressed: () => _editCategory(context, ref, c),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.shield_outlined),
                        title: Text('Privacidade'),
                        subtitle: Text(
                          'Seus dados só podem ser acessados pela sua conta. Os áudios não são guardados: '
                          'apenas a transcrição fica registrada junto do lançamento.',
                        ),
                      ),
                      ListTile(
                        key: const Key('change-password'),
                        leading: const Icon(Icons.password_rounded),
                        title: const Text('Alterar senha'),
                        onTap: () => _changePassword(context, ref),
                      ),
                      ListTile(
                        key: const Key('logout'),
                        leading: Icon(Icons.logout_rounded, color: Theme.of(context).colorScheme.error),
                        title: Text('Sair', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        onTap: () async {
                          final ok = await confirmDialog(
                            context,
                            title: 'Sair',
                            message: 'Deseja sair da sua conta?',
                            confirmLabel: 'Sair',
                          );
                          if (!ok) return;
                          try {
                            await ref.read(authRepositoryProvider).signOut();
                          } catch (e) {
                            if (context.mounted) showFailure(context, e);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Alterar senha'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nova senha'),
                validator: (v) => (v ?? '').length < 8 ? 'A senha deve ter pelo menos 8 caracteres.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
                validator: (v) => v != password.text ? 'As senhas não conferem.' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final newPassword = password.text;
    password.dispose();
    confirm.dispose();
    if (ok != true) return;
    try {
      await ref.read(authRepositoryProvider).updatePassword(newPassword);
      if (context.mounted) showMessage(context, 'Senha alterada.');
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<String?> _askText(BuildContext context, {required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref, [Account? account]) async {
    final name = TextEditingController(text: account?.name ?? '');
    final initial = TextEditingController(
      text: account == null ? '' : Money.format(account.initialBalanceCents.abs()).replaceFirst('R\$ ', ''),
    );
    var type = account?.type ?? AccountType.checking;
    var include = account?.includeInBalance ?? true;
    var negative = (account?.initialBalanceCents ?? 0) < 0;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(account == null ? 'Nova conta' : 'Editar conta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => type = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: initial,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CentsInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Saldo inicial', prefixText: 'R\$ '),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: negative,
                  onChanged: (v) => setState(() => negative = v ?? false),
                  title: const Text('Saldo inicial negativo'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: include,
                  onChanged: (v) => setState(() => include = v),
                  title: const Text('Incluir no saldo atual'),
                ),
              ],
            ),
          ),
          actions: [
            if (account != null)
              TextButton(
                onPressed: () => Navigator.pop(c, 'archive'),
                child: Text(account.archived ? 'Reativar' : 'Arquivar'),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    try {
      final repo = ref.read(catalogRepositoryProvider);
      if (action == 'archive') {
        await repo.archiveAccount(account!.id, archived: !account.archived);
      } else if (action == 'save') {
        if (name.text.trim().isEmpty) throw const FormatException();
        final cents = Money.parse(initial.text) ?? 0;
        await repo.saveAccount(
          id: account?.id,
          name: name.text,
          type: type,
          initialBalanceCents: negative ? -cents : cents,
          includeInBalance: include,
        );
      }
      if (action != null) ref.read(financeRevisionProvider.notifier).bump();
    } on FormatException {
      if (context.mounted) showMessage(context, 'Informe o nome da conta.', error: true);
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    } finally {
      name.dispose();
      initial.dispose();
    }
  }

  Future<void> _editCategory(BuildContext context, WidgetRef ref, [Category? category]) async {
    final name = TextEditingController(text: category?.name ?? '');
    var kind = category?.kind ?? CategoryKind.expense;
    var icon = category?.icon ?? 'category';
    var color = category?.color ?? categoryColors.first;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(category == null ? 'Nova categoria' : 'Editar categoria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
                ),
                const SizedBox(height: 12),
                SegmentedButton<CategoryKind>(
                  segments: const [
                    ButtonSegment(value: CategoryKind.expense, label: Text('Despesa')),
                    ButtonSegment(value: CategoryKind.income, label: Text('Receita')),
                  ],
                  selected: {kind},
                  onSelectionChanged: category == null ? (s) => setState(() => kind = s.first) : null,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in categoryIcons.entries)
                      ChoiceChip(
                        label: Icon(e.value, size: 18),
                        selected: icon == e.key,
                        onSelected: (_) => setState(() => icon = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final hex in categoryColors)
                      GestureDetector(
                        onTap: () => setState(() => color = hex),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: colorFromHex(hex),
                          child: color == hex ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (category != null)
              TextButton(
                onPressed: () => Navigator.pop(c, 'archive'),
                child: Text(category.archived ? 'Reativar' : 'Arquivar'),
              ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    try {
      final repo = ref.read(catalogRepositoryProvider);
      if (action == 'archive') {
        await repo.archiveCategory(category!.id, archived: !category.archived);
      } else if (action == 'save') {
        if (name.text.trim().isEmpty) throw const FormatException();
        await repo.saveCategory(id: category?.id, name: name.text, kind: kind, icon: icon, color: color);
      }
      if (action != null) ref.read(financeRevisionProvider.notifier).bump();
    } on FormatException {
      if (context.mounted) showMessage(context, 'Informe o nome da categoria.', error: true);
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    } finally {
      name.dispose();
    }
  }
}
