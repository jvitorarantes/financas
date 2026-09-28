import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/summaries.dart';
import 'budget_rules.dart';

enum AlertSeverity { info, warning, danger }

class FinancialAlert {
  const FinancialAlert(this.message, this.severity, {this.kind = ''});
  final String message;
  final AlertSeverity severity;
  final String kind;

  @override
  String toString() => message;
}

/// Alertas do dashboard, calculados só com os dados registrados.
List<FinancialAlert> buildDashboardAlerts({
  required DashboardSummary summary,
  required List<BudgetStatus> budgets,
  required DateTime today,
}) {
  final alerts = <FinancialAlert>[];
  final sameMonth = summary.month.year == today.year && summary.month.month == today.month;

  // 1. Orçamentos por nível de uso (o mais grave primeiro).
  final sorted = [...budgets]..sort((a, b) => b.usedPercent.compareTo(a.usedPercent));
  for (final b in sorted) {
    final level = b.level;
    if (level == BudgetLevel.normal) continue;
    final name = b.isOverall ? 'mensal' : 'de ${b.categoryName.toLowerCase()}';
    if (level == BudgetLevel.exceeded) {
      alerts.add(
        FinancialAlert(
          'Você ultrapassou o orçamento $name em ${Money.format(-b.remainingCents)} (${b.usedPercent}%).',
          AlertSeverity.danger,
          kind: 'budget',
        ),
      );
    } else {
      alerts.add(
        FinancialAlert(
          'Você já utilizou ${b.usedPercent}% do orçamento $name.',
          level == BudgetLevel.critical ? AlertSeverity.danger : AlertSeverity.warning,
          kind: 'budget',
        ),
      );
    }
  }

  // 2. Ritmo de gastos: compara o gasto do mês com o proporcional do orçamento.
  if (sameMonth) {
    final overall = budgets.where((b) => b.isOverall).firstOrNull;
    final reference =
        overall?.limitCents ?? budgets.where((b) => !b.isOverall).fold<int>(0, (s, b) => s + b.limitCents);
    if (reference > 0) {
      final days = Dates.daysInMonth(today);
      final expected = (reference * today.day / days).round();
      // Pequena tolerância (10%) e só depois dos primeiros dias do mês.
      // Ritmo considera só o que já foi pago (as previstas ainda não aconteceram).
      if (today.day >= 5 &&
          summary.monthExpensePaidCents > expected * 1.1 &&
          summary.monthExpensePaidCents < reference) {
        alerts.add(
          const FinancialAlert(
            'Seus gastos estão acima do ritmo esperado para este mês.',
            AlertSeverity.warning,
            kind: 'pace',
          ),
        );
      }
    }
  }

  // 3. Contas previstas para este mês (só as do mês).
  if (summary.pendingExpenseCents > 0) {
    alerts.add(
      FinancialAlert(
        'Você tem ${Money.format(summary.pendingExpenseCents)} em contas previstas para este mês.',
        AlertSeverity.info,
        kind: 'pending',
      ),
    );
  }

  // 4. Saldo projetado negativo.
  if (summary.projectedBalanceCents < 0) {
    alerts.add(
      FinancialAlert(
        'Seu saldo projetado para o fim do mês é de ${Money.format(summary.projectedBalanceCents)}.',
        AlertSeverity.danger,
        kind: 'projected',
      ),
    );
  }
  return alerts;
}
