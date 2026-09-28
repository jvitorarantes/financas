import '../../core/money.dart';
import '../models/summaries.dart';

extension GoalRules on FinancialGoal {
  int get remainingCents => (targetCents - currentCents).clamp(0, targetCents);
  int get percent => Money.percent(currentCents, targetCents).clamp(0, 100);
  bool get isCompleted => currentCents >= targetCents;

  /// Quanto guardar por mês para chegar na data (null sem data ou já atingida).
  int? monthlyNeededCents(DateTime today) {
    final target = targetDate;
    if (target == null || isCompleted) return null;
    var months = (target.year - today.year) * 12 + (target.month - today.month);
    if (target.day < today.day) months -= 1;
    if (months < 1) months = 1;
    return (remainingCents / months).ceil();
  }
}
