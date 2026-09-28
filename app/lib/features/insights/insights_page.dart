import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/ai_repository.dart';
import '../../domain/models/summaries.dart';

/// Análises salvas do mês; "Gerar análise" recalcula no servidor.
class InsightsNotifier extends AsyncNotifier<List<Insight>> {
  @override
  Future<List<Insight>> build() {
    final month = ref.watch(selectedMonthProvider);
    return ref.watch(aiRepositoryProvider).savedInsights(month);
  }

  Future<void> generate() async {
    final month = ref.read(selectedMonthProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(aiRepositoryProvider).insights(month));
  }
}

final insightsProvider = AsyncNotifierProvider<InsightsNotifier, List<Insight>>(InsightsNotifier.new);

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final insights = ref.watch(insightsProvider);
    final notifier = ref.read(insightsProvider.notifier);
    final monthNotifier = ref.read(selectedMonthProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análises'),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          ResponsiveCenter(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Análise do mês com IA',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Compara categorias, meses e orçamentos usando somente os seus lançamentos. '
                          'Cada análise mostra os números usados.',
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: insights.isLoading ? null : notifier.generate,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Gerar análise'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AsyncView<List<Insight>>(
                  value: insights,
                  onRetry: notifier.generate,
                  data: (list) => list.isEmpty
                      ? const EmptyState(
                          icon: Icons.insights_rounded,
                          title: 'Nenhuma análise para este mês',
                          message: 'Toque em "Gerar análise" para ver seus padrões de gastos.',
                        )
                      : Column(children: [for (final i in list) _InsightCard(insight: i)]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final Insight insight;

  static const _labels = {
    'total_expense_cents': 'Total de despesas',
    'current_cents': 'Este mês',
    'previous_cents': 'Mês anterior',
    'change_percent': 'Variação',
    'spent_cents': 'Utilizado',
    'limit_cents': 'Limite',
    'used_percent': 'Uso do orçamento',
    'monthly_recurring_cents': 'Recorrentes por mês',
    'count': 'Quantidade',
    'income_cents': 'Receitas',
    'expense_cents': 'Despesas',
    'balance_cents': 'Resultado',
    'potential_savings_cents': 'Economia possível',
    'category': 'Categoria',
  };

  String _value(String key, Object? v) {
    if (v is num && (key.endsWith('_cents') || key.startsWith('category:'))) return Money.format(v.toInt());
    if (v is num && key.endsWith('_percent')) return '${v.toInt()}%';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.financeColors;
    final (icon, color) = switch (insight.severity) {
      'warning' => (Icons.warning_amber_rounded, colors.warning),
      'positive' => (Icons.thumb_up_alt_rounded, colors.income),
      _ => (Icons.lightbulb_outline_rounded, colors.transfer),
    };
    final metrics = insight.metrics.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(insight.body),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in metrics)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${_labels[m.key] ?? m.key.replaceFirst('category:', '')}: ${_value(m.key, m.value)}',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
