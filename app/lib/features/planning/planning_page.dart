import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/summaries.dart';
import '../../domain/models/transaction.dart';
import '../transactions/transaction_tile.dart';

final pendingTransactionsProvider = FutureProvider<List<FinanceTransaction>>((ref) {
  ref.watch(financeRevisionProvider);
  final until = Dates.lastOfMonth(Dates.addMonths(Dates.today(), 3));
  return ref.watch(transactionsRepositoryProvider).pending(until: until);
});

final recurringProvider = FutureProvider<List<RecurringTransaction>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).recurring();
});

final currentMonthSummaryProvider = FutureProvider<DashboardSummary>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).summary(Dates.today());
});

class PlanningPage extends ConsumerWidget {
  const PlanningPage({super.key});

  Future<void> _markPaid(BuildContext context, WidgetRef ref, FinanceTransaction t) async {
    final today = Dates.today();
    final when = t.date.isAfter(today) ? today : t.date;
    try {
      await ref.read(transactionsRepositoryProvider).markPaid(t.id, on: when);
      ref.read(financeRevisionProvider.notifier).bump();
      if (context.mounted) {
        showMessage(context, t.type == TransactionType.income ? 'Marcado como recebido.' : 'Marcado como pago.');
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTransactionsProvider);
    final recurring = ref.watch(recurringProvider);
    final summary = ref.watch(currentMonthSummaryProvider);
    final colors = context.financeColors;
    final today = Dates.today();

    return Scaffold(
      appBar: AppBar(title: const Text('Planejamento')),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(financeRevisionProvider.notifier).bump(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            ResponsiveCenter(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- saldo atual x projetado ----
                  if (summary.value case final s?)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _Figure(label: 'Saldo atual', cents: s.currentBalanceCents),
                                ),
                                Expanded(
                                  child: _Figure(label: 'Projetado (fim do mês)', cents: s.projectedBalanceCents),
                                ),
                              ],
                            ),
                            const Divider(height: 28),
                            Row(
                              children: [
                                Expanded(
                                  child: _Figure(
                                    label: 'A pagar no mês',
                                    cents: s.pendingExpenseCents,
                                    color: colors.expense,
                                  ),
                                ),
                                Expanded(
                                  child: _Figure(
                                    label: 'A receber no mês',
                                    cents: s.pendingIncomeCents,
                                    color: colors.income,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'O saldo atual considera só o que já foi pago ou recebido. O projetado desconta as contas '
                              'pendentes até o fim do mês; receitas futuras não entram como dinheiro disponível.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Contas e vencimentos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  AsyncView<List<FinanceTransaction>>(
                    value: pending,
                    onRetry: () => ref.invalidate(pendingTransactionsProvider),
                    data: (items) {
                      if (items.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Nenhuma conta futura. Registre uma despesa com data futura, parcelada ou recorrente.',
                            ),
                          ),
                        );
                      }
                      final groups = <String, List<FinanceTransaction>>{};
                      for (final t in items) {
                        final key = t.date.isBefore(today) ? 'Vencidas' : Dates.monthLabel(t.date);
                        groups.putIfAbsent(key, () => []).add(t);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: Theme.of(context).textTheme.labelLarge
                                          ?.copyWith(color: entry.key == 'Vencidas' ? colors.expense : null),
                                    ),
                                  ),
                                  MoneyText(
                                    entry.value.fold<int>(0, (s, t) => s + t.signedCents),
                                    colored: true,
                                    style: Theme.of(context).textTheme.labelLarge,
                                  ),
                                ],
                              ),
                            ),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Column(
                                  children: [
                                    for (final t in entry.value)
                                      TransactionTile(
                                        transaction: t,
                                        onTap: () => context.push('/transactions/edit', extra: t),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                MoneyText(
                                                  t.amountCents,
                                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                                ),
                                                Text(
                                                  'Vence ${Dates.formatShort(t.date)}',
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                              ],
                                            ),
                                            IconButton(
                                              tooltip: t.type == TransactionType.income
                                                  ? 'Marcar como recebido'
                                                  : 'Marcar como pago',
                                              onPressed: () => _markPaid(context, ref, t),
                                              icon: const Icon(Icons.check_circle_outline_rounded),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recorrências',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  AsyncView<List<RecurringTransaction>>(
                    value: recurring,
                    onRetry: () => ref.invalidate(recurringProvider),
                    data: (items) => items.isEmpty
                        ? const Card(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Nenhuma receita ou despesa recorrente. Marque "Recorrente" ao registrar um lançamento.',
                              ),
                            ),
                          )
                        : Card(
                            child: Column(
                              children: [
                                for (final r in items)
                                  SwitchListTile(
                                    title: Text(r.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${r.type.label} · ${r.everyLabel} · ${Money.format(r.amountCents)}'
                                      '${r.endDate != null ? ' · até ${Dates.format(r.endDate!)}' : ''}',
                                    ),
                                    value: r.active,
                                    onChanged: (v) async {
                                      if (!v) {
                                        final ok = await confirmDialog(
                                          context,
                                          title: 'Encerrar recorrência',
                                          message:
                                              'As próximas ocorrências pendentes de "${r.description}" serão removidas.',
                                          confirmLabel: 'Encerrar',
                                        );
                                        if (!ok) return;
                                      }
                                      try {
                                        await ref.read(financeRepositoryProvider).setRecurringActive(r.id, v);
                                        if (v) await ref.read(transactionsRepositoryProvider).materializeRecurring();
                                        ref.read(financeRevisionProvider.notifier).bump();
                                      } catch (e) {
                                        if (context.mounted) showFailure(context, e);
                                      }
                                    },
                                  ),
                              ],
                            ),
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

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.cents, this.color});
  final String label;
  final int cents;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: MoneyText(
          cents,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
        ),
      ),
    ],
  );
}
