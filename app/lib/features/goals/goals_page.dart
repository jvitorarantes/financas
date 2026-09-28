import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/finance/goal_rules.dart';
import '../../domain/models/summaries.dart';

final goalsProvider = FutureProvider<List<FinancialGoal>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).goals();
});

class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  Future<void> _editGoal(BuildContext context, WidgetRef ref, [FinancialGoal? goal]) async {
    final result = await showDialog<_GoalInput>(
      context: context,
      builder: (_) => _GoalDialog(goal: goal),
    );
    if (result == null) return;
    try {
      final repo = ref.read(financeRepositoryProvider);
      if (result.delete) {
        await repo.deleteGoal(goal!.id);
      } else {
        await repo.saveGoal(
          id: goal?.id,
          name: result.name,
          targetCents: result.targetCents,
          targetDate: result.targetDate,
        );
      }
      ref.read(financeRevisionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _adjust(BuildContext context, WidgetRef ref, FinancialGoal goal, {required bool add}) async {
    final controller = TextEditingController();
    final cents = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(add ? 'Guardar dinheiro' : 'Retirar dinheiro'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [CentsInputFormatter()],
          decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, Money.parse(controller.text)), child: const Text('Confirmar')),
        ],
      ),
    );
    controller.dispose();
    if (cents == null || cents <= 0) return;
    try {
      final next = add ? goal.currentCents + cents : goal.currentCents - cents;
      await ref.read(financeRepositoryProvider).setGoalAmount(goal.id, next.clamp(0, Money.maxCents));
      ref.read(financeRevisionProvider.notifier).bump();
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas'),
        actions: [
          TextButton.icon(
            key: const Key('goal-add'),
            onPressed: () => _editGoal(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nova meta'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AsyncView<List<FinancialGoal>>(
        value: goals,
        onRetry: () => ref.invalidate(goalsProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.flag_rounded,
                title: 'Crie sua primeira meta',
                message: 'Ex.: "Guardar R\$ 5.000", "Comprar um celular" ou "Montar reserva".',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  ResponsiveCenter(
                    maxWidth: 800,
                    child: Column(
                      children: [
                        for (final g in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _GoalCard(
                              goal: g,
                              onEdit: () => _editGoal(context, ref, g),
                              onAdd: () => _adjust(context, ref, g, add: true),
                              onWithdraw: () => _adjust(context, ref, g, add: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onEdit, required this.onAdd, required this.onWithdraw});
  final FinancialGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onAdd;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    final theme = Theme.of(context);
    final monthly = g.monthlyNeededCents(Dates.today());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  g.isCompleted ? Icons.emoji_events_rounded : Icons.savings_rounded,
                  color: g.isCompleted ? context.financeColors.warning : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                IconButton(tooltip: 'Editar meta', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(g.currentCents, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('de ${Money.format(g.targetCents)}', style: theme.textTheme.bodySmall),
                const Spacer(),
                Text('${g.percent}%', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(value: g.percent / 100, minHeight: 10),
            ),
            const SizedBox(height: 8),
            Text(
              g.isCompleted
                  ? 'Meta atingida! 🎉'
                  : [
                      'Faltam ${Money.format(g.remainingCents)}',
                      if (g.targetDate != null) 'até ${Dates.format(g.targetDate!)}',
                      if (monthly != null) '(${Money.format(monthly)} por mês)',
                    ].join(' '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onWithdraw, child: const Text('Retirar')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: onAdd, child: const Text('Guardar')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalInput {
  const _GoalInput({this.name = '', this.targetCents = 0, this.targetDate, this.delete = false});
  final String name;
  final int targetCents;
  final DateTime? targetDate;
  final bool delete;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({this.goal});
  final FinancialGoal? goal;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _name = TextEditingController(text: widget.goal?.name ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : Money.format(widget.goal!.targetCents).replaceFirst('R\$ ', ''),
  );
  late DateTime? _date = widget.goal?.targetDate;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.goal == null ? 'Nova meta' : 'Editar meta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            inputFormatters: [CentsInputFormatter()],
            decoration: const InputDecoration(labelText: 'Valor objetivo', prefixText: 'R\$ '),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date ?? Dates.addMonths(Dates.today(), 6),
                firstDate: Dates.today(),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text(_date == null ? 'Data objetivo (opcional)' : 'Até ${Dates.format(_date!)}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (widget.goal != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _GoalInput(delete: true)),
            child: const Text('Excluir'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final cents = Money.parse(_target.text);
            if (_name.text.trim().isEmpty) return setState(() => _error = 'Dê um nome para a meta.');
            if (cents == null || cents <= 0) return setState(() => _error = 'Informe um valor maior que zero.');
            Navigator.pop(context, _GoalInput(name: _name.text, targetCents: cents, targetDate: _date));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
