import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/finance/alerts.dart';
import '../../domain/finance/budget_rules.dart';
import '../../domain/models/summaries.dart';
import '../audio/audio_record_sheet.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    // Gera as próximas ocorrências das recorrências (idempotente no banco).
    Future.microtask(() async {
      try {
        final created = await ref.read(transactionsRepositoryProvider).materializeRecurring();
        if (created > 0 && mounted) ref.read(financeRevisionProvider.notifier).bump();
      } catch (_) {
        /* não bloqueia o dashboard */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(dashboardSummaryProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(financeRevisionProvider.notifier).bump();
          await ref.read(dashboardSummaryProvider.future);
        },
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              sliver: SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, wide ? 32 : 96),
                sliver: SliverToBoxAdapter(
                  child: ResponsiveCenter(
                    child: AsyncView<DashboardSummary>(
                      value: summary,
                      onRetry: () => ref.read(financeRevisionProvider.notifier).bump(),
                      data: (s) => wide ? _WideLayout(summary: s) : _NarrowLayout(summary: s),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MonthHeader(),
        gap,
        _BalanceCard(summary: summary),
        gap,
        _IncomeExpenseRow(summary: summary),
        gap,
        const _VoiceCard(),
        gap,
        _AlertsCard(summary: summary),
        const _BudgetCard(),
        gap,
        const _CategoryCard(),
        gap,
        const _RecentCard(),
      ],
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MonthHeader(),
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BalanceCard(summary: summary),
                  gap,
                  _IncomeExpenseRow(summary: summary),
                  gap,
                  const _CategoryCard(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _VoiceCard(),
                  gap,
                  _AlertsCard(summary: summary),
                  const _BudgetCard(),
                  gap,
                  const _RecentCard(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthHeader extends ConsumerWidget {
  const _MonthHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Visão geral',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(tooltip: 'Mês anterior', onPressed: notifier.previous, icon: const Icon(Icons.chevron_left_rounded)),
        Text(Dates.monthLabel(month), style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(tooltip: 'Próximo mês', onPressed: notifier.next, icon: const Icon(Icons.chevron_right_rounded)),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onPrimary = scheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, const Color(0xFF7C3AED), 0.55)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo atual', style: TextStyle(color: onPrimary.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              summary.currentBalanceCents,
              key: const Key('current-balance'),
              style: TextStyle(color: onPrimary, fontSize: 36, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.trending_flat_rounded, color: onPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saldo projetado no fim do mês',
                    style: TextStyle(color: onPrimary.withValues(alpha: 0.9), fontSize: 13),
                  ),
                ),
                MoneyText(
                  summary.projectedBalanceCents,
                  key: const Key('projected-balance'),
                  style: TextStyle(color: onPrimary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (summary.pendingIncomeCents > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Não inclui ${Money.format(summary.pendingIncomeCents)} a receber.',
              style: TextStyle(color: onPrimary.withValues(alpha: 0.75), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _IncomeExpenseRow extends StatelessWidget {
  const _IncomeExpenseRow({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.financeColors;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Receitas do mês',
            cents: summary.monthIncomeCents,
            icon: Icons.arrow_downward_rounded,
            color: colors.income,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Despesas do mês',
            cents: summary.monthExpenseCents,
            icon: Icons.arrow_upward_rounded,
            color: colors.expense,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.cents, required this.icon, required this.color});
  final String label;
  final int cents;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(cents, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAudioRecorderSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                child: Icon(Icons.mic_rounded, color: scheme.onPrimary, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registrar por voz',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '"Gastei 85 reais de gasolina hoje no cartão"',
                      style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
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
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetStatusProvider).value ?? const <BudgetStatus>[];
    final alerts = buildDashboardAlerts(summary: summary, budgets: budgets, today: Dates.today());
    if (alerts.isEmpty) return const SizedBox.shrink();
    final colors = context.financeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        title: 'Alertas',
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          children: [
            for (final a in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (a.severity) {
                        AlertSeverity.danger => Icons.error_rounded,
                        AlertSeverity.warning => Icons.warning_amber_rounded,
                        AlertSeverity.info => Icons.info_rounded,
                      },
                      size: 20,
                      color: switch (a.severity) {
                        AlertSeverity.danger => colors.expense,
                        AlertSeverity.warning => colors.warning,
                        AlertSeverity.info => colors.transfer,
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.message)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetStatusProvider);
    return SectionCard(
      title: 'Orçamento do mês',
      action: TextButton(onPressed: () => context.go('/budget'), child: const Text('Ver tudo')),
      child: AsyncView<List<BudgetStatus>>(
        value: budgets,
        onRetry: () => ref.invalidate(budgetStatusProvider),
        data: (list) {
          if (list.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Defina limites mensais para acompanhar seus gastos.'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => context.go('/budget'), child: const Text('Definir orçamento')),
              ],
            );
          }
          final overall = list.where((b) => b.isOverall).firstOrNull;
          final limit = overall?.limitCents ?? list.fold<int>(0, (s, b) => s + b.limitCents);
          final spent = overall?.spentCents ?? list.fold<int>(0, (s, b) => s + b.spentCents);
          final percent = Money.percent(spent, limit);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _kv(context, 'Orçamento', Money.format(limit))),
                  Expanded(child: _kv(context, 'Utilizado', Money.format(spent))),
                  Expanded(child: _kv(context, 'Restante', Money.format(limit - spent))),
                ],
              ),
              const SizedBox(height: 14),
              UsageBar(percent: percent),
              const SizedBox(height: 6),
              Text(
                '$percent% utilizado · ${BudgetLevel.forPercent(percent).label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spending = ref.watch(spendingByCategoryProvider);
    return SectionCard(
      title: 'Gastos por categoria',
      child: AsyncView<List<CategorySpending>>(
        value: spending,
        onRetry: () => ref.invalidate(spendingByCategoryProvider),
        data: (list) {
          if (list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhuma despesa registrada neste mês.'),
            );
          }
          final total = list.fold<int>(0, (s, c) => s + c.totalCents);
          return Column(
            children: [
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 58,
                        sections: [
                          for (final c in list)
                            PieChartSectionData(
                              value: c.totalCents.toDouble(),
                              color: colorFromHex(c.color),
                              radius: 26,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Total', style: Theme.of(context).textTheme.bodySmall),
                        MoneyText(total, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final c in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CategoryAvatar(icon: c.icon, color: c.color, size: 36),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${Money.percent(c.totalCents, total)}% · ${c.count} lançamento(s)'),
                  trailing: MoneyText(c.totalCents, style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => context.go('/transactions'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider);
    return SectionCard(
      title: 'Últimas movimentações',
      action: TextButton(onPressed: () => context.go('/transactions'), child: const Text('Ver todas')),
      child: AsyncView(
        value: recent,
        onRetry: () => ref.invalidate(recentTransactionsProvider),
        data: (list) => list.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Suas movimentações aparecem aqui. Toque em "+" ou grave um áudio.'),
              )
            : Column(
                children: [
                  for (final t in list)
                    TransactionTile(
                      transaction: t,
                      onTap: () => context.push('/transactions/edit', extra: t),
                    ),
                ],
              ),
      ),
    );
  }
}
