import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/models/account.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/summaries.dart';

final recurringProvider = FutureProvider<List<RecurringTransaction>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).recurring();
});

/// Aba "Recorrentes": ver, editar, pausar e excluir receitas/despesas recorrentes.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurring = ref.watch(recurringProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recorrentes')),
      body: AsyncView<List<RecurringTransaction>>(
        value: recurring,
        onRetry: () => ref.invalidate(recurringProvider),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.repeat_rounded,
              title: 'Nenhuma recorrência',
              message: 'Ao registrar uma receita ou despesa, escolha "Recorrente" (ex.: aluguel, salário, academia).',
            );
          }
          final active = items.where((r) => r.active).toList();
          final paused = items.where((r) => !r.active).toList();
          final monthlyExpense = active
              .where((r) => r.type == TransactionType.expense)
              .fold<int>(0, (s, r) => s + _monthlyEquivalent(r));
          final monthlyIncome = active
              .where((r) => r.type == TransactionType.income)
              .fold<int>(0, (s, r) => s + _monthlyEquivalent(r));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recurringProvider),
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
                          child: Row(
                            children: [
                              Expanded(child: _Figure('Despesas fixas / mês', -monthlyExpense)),
                              Expanded(child: _Figure('Receitas fixas / mês', monthlyIncome)),
                            ],
                          ),
                        ),
                      ),
                      if (active.isNotEmpty) ...[
                        const _Header('Ativas'),
                        for (final r in active) _RecurringCard(recurring: r),
                      ],
                      if (paused.isNotEmpty) ...[
                        const _Header('Pausadas'),
                        for (final r in paused) _RecurringCard(recurring: r),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _monthlyEquivalent(RecurringTransaction r) => switch (r.frequency) {
    RecurrenceFrequency.weekly => (r.amountCents * 52 / 12 / r.intervalCount).round(),
    RecurrenceFrequency.yearly => (r.amountCents / 12 / r.intervalCount).round(),
    RecurrenceFrequency.monthly => (r.amountCents / r.intervalCount).round(),
  };
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.cents);
  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: MoneyText(cents, colored: true, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
    ],
  );
}

class _RecurringCard extends ConsumerWidget {
  const _RecurringCard({required this.recurring});
  final RecurringTransaction recurring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = recurring;
    final colors = context.financeColors;
    final next = r.active ? r.nextOccurrence(Dates.today()) : null;
    final details = [
      r.everyLabel,
      if (next != null) 'Próximo: ${Dates.format(next)}' else if (r.active) 'Encerrada',
      if (r.endDate != null) 'até ${Dates.format(r.endDate!)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          key: ValueKey('recurring-${r.id}'),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          leading: CategoryAvatar(
            icon: r.categoryIcon ?? 'repeat',
            color: r.categoryColor,
            iconData: r.categoryIcon == null ? Icons.repeat_rounded : null,
          ),
          title: Text(
            r.description,
            style: TextStyle(fontWeight: FontWeight.w700, color: r.active ? null : Theme.of(context).disabledColor),
          ),
          subtitle: Text(
            '${[r.categoryName ?? 'Sem categoria', r.accountName ?? ''].where((e) => e.isNotEmpty).join(' · ')}\n$details',
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${r.type == TransactionType.income ? '+' : '-'}${Money.format(r.amountCents)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: r.type == TransactionType.income ? colors.income : colors.expense,
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('recurring-menu-${r.id}'),
                tooltip: 'Ações',
                onSelected: (action) => switch (action) {
                  'edit' => _edit(context, ref, r),
                  'toggle' => _toggle(context, ref, r),
                  _ => _delete(context, ref, r),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'toggle', child: Text(r.active ? 'Pausar' : 'Reativar')),
                  const PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
            ],
          ),
          onTap: () => _edit(context, ref, r),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    final accounts = await ref.read(accountsProvider.future);
    final categories = await ref.read(categoriesProvider.future);
    if (!context.mounted) return;
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditRecurringDialog(recurring: r, accounts: accounts, categories: categories),
    );
    if (changes == null || changes.isEmpty) return;
    try {
      await ref.read(financeRepositoryProvider).updateRecurring(r.id, changes);
      ref.read(financeRevisionProvider.notifier).bump();
      if (context.mounted) showMessage(context, 'Recorrência atualizada. Os próximos lançamentos foram ajustados.');
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    if (r.active) {
      final ok = await confirmDialog(
        context,
        title: 'Pausar recorrência',
        message: 'Os próximos lançamentos previstos de "${r.description}" serão removidos. Você pode reativar depois.',
        confirmLabel: 'Pausar',
      );
      if (!ok) return;
    }
    try {
      await ref.read(financeRepositoryProvider).setRecurringActive(r.id, !r.active);
      if (!r.active) await ref.read(transactionsRepositoryProvider).materializeRecurring();
      ref.read(financeRevisionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir recorrência',
      message:
          '"${r.description}" deixa de se repetir e os lançamentos previstos serão apagados. '
          'O que já foi pago continua no histórico.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(financeRepositoryProvider).deleteRecurring(r.id);
      ref.read(financeRevisionProvider.notifier).bump();
      if (context.mounted) showMessage(context, 'Recorrência excluída.');
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }
}

class _EditRecurringDialog extends StatefulWidget {
  const _EditRecurringDialog({required this.recurring, required this.accounts, required this.categories});
  final RecurringTransaction recurring;
  final List<Account> accounts;
  final List<Category> categories;

  @override
  State<_EditRecurringDialog> createState() => _EditRecurringDialogState();
}

class _EditRecurringDialogState extends State<_EditRecurringDialog> {
  late final RecurringTransaction r = widget.recurring;
  late final _description = TextEditingController(text: r.description);
  late final _amount = TextEditingController(text: Money.format(r.amountCents).replaceFirst('R\$ ', ''));
  late String? _categoryId = r.categoryId;
  late String? _accountId = r.accountId;
  late String _every = r.frequency == RecurrenceFrequency.weekly
      ? 'w'
      : r.frequency == RecurrenceFrequency.yearly
      ? '12'
      : '${r.intervalCount}';
  // Duração: 0 = sem fim, 1–12 meses a partir do início, -1 = data final atual.
  late int _duration = r.endDate == null ? 0 : _monthsFor(r.endDate!) ?? -1;
  String? _error;

  int? _monthsFor(DateTime end) {
    for (var m = 1; m <= 12; m++) {
      if (Dates.addMonths(r.startDate, m).subtract(const Duration(days: 1)) == end) return m;
    }
    return null;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final cents = Money.parse(_amount.text);
    if (_description.text.trim().isEmpty) return setState(() => _error = 'Informe a descrição.');
    if (cents == null || cents <= 0) return setState(() => _error = 'Informe um valor maior que zero.');
    final weekly = _every == 'w';
    final changes = <String, dynamic>{
      'description': _description.text.trim(),
      'amount_cents': cents,
      'category_id': _categoryId ?? '',
      if (_accountId != null) 'account_id': _accountId,
      'frequency': weekly ? 'weekly' : 'monthly',
      'interval_count': weekly ? 1 : int.parse(_every),
      if (_duration == 0) 'end_date': '',
      if (_duration > 0)
        'end_date': Dates.iso(Dates.addMonths(r.startDate, _duration).subtract(const Duration(days: 1))),
    };
    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    final kind = r.type == TransactionType.income ? CategoryKind.income : CategoryKind.expense;
    final categories = widget.categories.where((c) => c.kind == kind && (!c.archived || c.id == _categoryId)).toList();
    final accounts = widget.accounts.where((a) => !a.archived || a.id == _accountId).toList();
    return AlertDialog(
      title: const Text('Editar recorrência'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('recurring-edit-description'),
                controller: _description,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Descrição', counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('recurring-edit-amount'),
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [CentsInputFormatter()],
                decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                  for (final c in categories)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(iconFor(c.icon), size: 18, color: colorFromHex(c.color)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: accounts.any((a) => a.id == _accountId) ? _accountId : null,
                decoration: const InputDecoration(labelText: 'Conta'),
                items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('recurring-edit-every'),
                isExpanded: true,
                initialValue: _every,
                decoration: const InputDecoration(labelText: 'Repetir'),
                items: [
                  const DropdownMenuItem(value: 'w', child: Text('Toda semana')),
                  const DropdownMenuItem(value: '1', child: Text('Todo mês')),
                  for (var m = 2; m <= 12; m++) DropdownMenuItem(value: '$m', child: Text('A cada $m meses')),
                ],
                onChanged: (v) => setState(() => _every = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('recurring-edit-duration'),
                isExpanded: true,
                initialValue: _duration,
                decoration: InputDecoration(labelText: 'Durante (desde ${Dates.format(r.startDate)})'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Sem data para acabar')),
                  if (_duration == -1 && r.endDate != null)
                    DropdownMenuItem(value: -1, child: Text('Até ${Dates.format(r.endDate!)}')),
                  for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(m == 1 ? '1 mês' : '$m meses')),
                ],
                onChanged: (v) => setState(() => _duration = v!),
              ),
              const SizedBox(height: 12),
              Text(
                'Os lançamentos previstos a partir de hoje serão refeitos com estes dados. '
                'O que já foi pago não muda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const Key('recurring-edit-save'), onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
