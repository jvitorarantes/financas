import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/domain/finance/alerts.dart';
import 'package:meu_financeiro/domain/finance/budget_rules.dart';
import 'package:meu_financeiro/domain/finance/goal_rules.dart';
import 'package:meu_financeiro/domain/models/summaries.dart';

DashboardSummary summary({int expense = 0, int pending = 0, int projected = 100000, DateTime? month}) =>
    DashboardSummary(
      month: month ?? DateTime(2026, 9),
      currentBalanceCents: 100000,
      monthIncomeCents: 0,
      monthExpenseCents: expense,
      pendingExpenseCents: pending,
      pendingIncomeCents: 0,
      projectedBalanceCents: projected,
    );

BudgetStatus budget(String name, int limit, int spent, {String? categoryId = 'c'}) => BudgetStatus(
  budgetId: name,
  categoryId: categoryId,
  categoryName: name,
  icon: 'category',
  color: '#000000',
  limitCents: limit,
  spentCents: spent,
);

void main() {
  group('orçamento', () {
    test('utilizado, restante e percentual', () {
      final b = budget('Alimentação', 100000, 82000);
      expect(b.usedPercent, 82);
      expect(b.remainingCents, 18000);
      expect(b.level, BudgetLevel.attention);
    });

    test('níveis de utilização', () {
      expect(BudgetLevel.forPercent(50), BudgetLevel.normal);
      expect(BudgetLevel.forPercent(70), BudgetLevel.attention);
      expect(BudgetLevel.forPercent(90), BudgetLevel.critical);
      expect(BudgetLevel.forPercent(100), BudgetLevel.exceeded);
      expect(BudgetLevel.forPercent(150), BudgetLevel.exceeded);
    });
  });

  group('alertas do dashboard', () {
    final today = DateTime(2026, 9, 15);

    test('orçamento de alimentação em 82%', () {
      final alerts = buildDashboardAlerts(
        summary: summary(),
        budgets: [budget('Alimentação', 100000, 82000)],
        today: today,
      );
      expect(alerts.map((a) => a.message), contains('Você já utilizou 82% do orçamento de alimentação.'));
    });

    test('orçamento estourado', () {
      final alerts = buildDashboardAlerts(summary: summary(), budgets: [budget('Lazer', 40000, 50000)], today: today);
      expect(alerts.first.message, 'Você ultrapassou o orçamento de lazer em R\$ 100,00 (125%).');
      expect(alerts.first.severity, AlertSeverity.danger);
    });

    test('gastos acima do ritmo esperado', () {
      // Metade do mês, orçamento geral de R$ 3.000: esperado ~R$ 1.500.
      final alerts = buildDashboardAlerts(
        summary: summary(expense: 200000),
        budgets: [budget('Geral', 300000, 200000, categoryId: null)],
        today: today,
      );
      expect(alerts.map((a) => a.message), contains('Seus gastos estão acima do ritmo esperado para este mês.'));
    });

    test('ritmo normal não gera alerta', () {
      final alerts = buildDashboardAlerts(
        summary: summary(expense: 100000),
        budgets: [budget('Geral', 300000, 100000, categoryId: null)],
        today: today,
      );
      expect(alerts.where((a) => a.kind == 'pace'), isEmpty);
    });

    test('contas futuras', () {
      final alerts = buildDashboardAlerts(summary: summary(pending: 80000), budgets: const [], today: today);
      expect(alerts.single.message, 'Você possui R\$ 800,00 em contas futuras.');
    });

    test('saldo projetado negativo', () {
      final alerts = buildDashboardAlerts(summary: summary(projected: -5000), budgets: const [], today: today);
      expect(alerts.single.kind, 'projected');
    });

    test('sem dados, sem alertas', () {
      expect(buildDashboardAlerts(summary: summary(), budgets: const [], today: today), isEmpty);
    });
  });

  group('metas', () {
    const goal = FinancialGoal(id: 'g', name: 'Reserva', targetCents: 500000, currentCents: 125000);

    test('progresso', () {
      expect(goal.percent, 25);
      expect(goal.remainingCents, 375000);
      expect(goal.isCompleted, isFalse);
    });

    test('quanto guardar por mês até a data', () {
      final withDate = FinancialGoal(
        id: 'g',
        name: 'Celular',
        targetCents: 300000,
        currentCents: 0,
        targetDate: DateTime(2027, 3, 28),
      );
      expect(withDate.monthlyNeededCents(DateTime(2026, 9, 28)), 50000);
      expect(goal.monthlyNeededCents(DateTime(2026, 9, 28)), isNull);
    });

    test('meta atingida', () {
      const done = FinancialGoal(id: 'g', name: 'x', targetCents: 1000, currentCents: 1500);
      expect(done.isCompleted, isTrue);
      expect(done.percent, 100);
      expect(done.remainingCents, 0);
    });
  });
}
