import '../../core/money.dart';
import '../models/summaries.dart';

/// Níveis de utilização do orçamento.
enum BudgetLevel {
  normal('Dentro do orçamento'),
  attention('Atenção'),
  critical('Quase no limite'),
  exceeded('Orçamento estourado');

  const BudgetLevel(this.label);
  final String label;

  static BudgetLevel forPercent(int percent) {
    if (percent >= 100) return exceeded;
    if (percent >= 90) return critical;
    if (percent >= 70) return attention;
    return normal;
  }
}

extension BudgetStatusRules on BudgetStatus {
  int get remainingCents => limitCents - spentCents;
  int get usedPercent => Money.percent(spentCents, limitCents);
  BudgetLevel get level => BudgetLevel.forPercent(usedPercent);

  /// Quanto "deveria" ter sido gasto até [day] num ritmo uniforme.
  int expectedSpentCents(int day, int daysInMonth) => (limitCents * day / daysInMonth).round();
}
