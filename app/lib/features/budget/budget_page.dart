import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance/budget_rules.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/summaries.dart';

class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final budgets = ref.watch(budgetStatusProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final monthNotifier = ref.read(selectedMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamento'),
        actions: [
          IconButton(
            tooltip: 'Mês anterior',
            onPressed: monthNotifier.previous,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Center(child: Text(Dates.monthLabel(month))),
          IconButton(
            tooltip: 'Próximo mês',
            onPressed: monthNotifier.next,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'budget-add',
        onPressed: () => _edit(context, ref, categories: categories, existing: budgets.value ?? const []),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Definir limite'),
      ),
      body: AsyncView<List<BudgetStatus>>(
        value: budgets,
        onRetry: () => ref.invalidate(budgetStatusProvider),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.donut_large_rounded,
              title: 'Nenhum orçamento definido',
              message: 'Defina limites mensais por categoria (ex.: Alimentação R\$ 1.000) e acompanhe quanto já usou.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              ResponsiveCenter(
                maxWidth: 800,
                child: Column(
                  children: [
                    for (final b in list) ...[
                      _BudgetTile(
                        budget: b,
                        onTap: () => _edit(context, ref, categories: categories, existing: list, budget: b),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Os limites valem para todos os meses. Só despesas pagas contam como utilizadas.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required List<Category> categories,
    required List<BudgetStatus> existing,
    BudgetStatus? budget,
  }) async {
    final result = await showDialog<_BudgetInput>(
      context: context,
      builder: (_) => _BudgetDialog(
        categories: categories.where((c) => c.kind == CategoryKind.expense && !c.archived).toList(),
        budget: budget,
        taken: {
          for (final b in existing)
            if (b.budgetId != budget?.budgetId) b.categoryId ?? '__overall__',
        },
      ),
    );
    if (result == null) return;
    try {
      final repo = ref.read(financeRepositoryProvider);
      if (result.delete) {
        await repo.deleteBudget(budget!.budgetId);
      } else {
        await repo.saveBudget(categoryId: result.categoryId, amountCents: result.amountCents);
      }
      ref.read(financeRevisionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.budget, required this.onTap});
  final BudgetStatus budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = budget;
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar(icon: b.icon, color: b.color, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(b.categoryName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  Text('${b.usedPercent}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              UsageBar(percent: b.usedPercent),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Utilizado ${Money.format(b.spentCents)} de ${Money.format(b.limitCents)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    b.remainingCents >= 0
                        ? 'Restam ${Money.format(b.remainingCents)}'
                        : 'Excedeu ${Money.format(-b.remainingCents)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (b.level != BudgetLevel.normal) ...[
                const SizedBox(height: 6),
                Text(b.level.label, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetInput {
  const _BudgetInput({this.categoryId, this.amountCents = 0, this.delete = false});
  final String? categoryId;
  final int amountCents;
  final bool delete;
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.categories, required this.taken, this.budget});
  final List<Category> categories;
  final Set<String> taken;
  final BudgetStatus? budget;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late String _target = widget.budget == null ? '' : (widget.budget!.categoryId ?? '__overall__');
  late final _amount = TextEditingController(
    text: widget.budget == null ? '' : Money.format(widget.budget!.limitCents).replaceFirst('R\$ ', ''),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = <String, String>{
      '__overall__': 'Orçamento geral do mês',
      for (final c in widget.categories) c.id: c.name,
    }..removeWhere((k, _) => widget.taken.contains(k));
    return AlertDialog(
      title: Text(widget.budget == null ? 'Novo limite mensal' : 'Editar limite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _target.isEmpty ? null : _target,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: widget.budget != null ? null : (v) => setState(() => _target = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [CentsInputFormatter()],
            decoration: InputDecoration(labelText: 'Limite mensal', prefixText: 'R\$ ', errorText: _error),
          ),
        ],
      ),
      actions: [
        if (widget.budget != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _BudgetInput(delete: true)),
            child: const Text('Remover'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final cents = Money.parse(_amount.text);
            if (_target.isEmpty) return setState(() => _error = 'Escolha a categoria.');
            if (cents == null || cents <= 0) return setState(() => _error = 'Informe um valor maior que zero.');
            Navigator.pop(
              context,
              _BudgetInput(categoryId: _target == '__overall__' ? null : _target, amountCents: cents),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
