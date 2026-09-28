import '../../core/dates.dart';
import 'enums.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.month,
    required this.currentBalanceCents,
    required this.monthIncomeCents,
    required this.monthExpenseCents,
    int? monthExpensePaidCents,
    this.monthIncomePendingCents = 0,
    required this.pendingExpenseCents,
    required this.pendingIncomeCents,
    required this.projectedBalanceCents,
  }) : monthExpensePaidCents = monthExpensePaidCents ?? monthExpenseCents;

  /// Despesas previstas (ainda não pagas) do mês.
  int get monthExpensePendingCents => monthExpenseCents - monthExpensePaidCents;

  final DateTime month;
  final int currentBalanceCents;
  final int monthIncomeCents;
  final int monthExpenseCents;

  /// Despesas do mês já pagas (o restante de [monthExpenseCents] é previsto).
  final int monthExpensePaidCents;
  final int monthIncomePendingCents;
  final int pendingExpenseCents;
  final int pendingIncomeCents;
  final int projectedBalanceCents;

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    int c(String k) => (j[k] as num?)?.toInt() ?? 0;
    return DashboardSummary(
      month: Dates.parseIso(j['month'] as String),
      currentBalanceCents: c('current_balance_cents'),
      monthIncomeCents: c('month_income_cents'),
      monthExpenseCents: c('month_expense_cents'),
      monthExpensePaidCents: j.containsKey('month_expense_paid_cents') ? c('month_expense_paid_cents') : null,
      monthIncomePendingCents: c('month_income_pending_cents'),
      pendingExpenseCents: c('pending_expense_cents'),
      pendingIncomeCents: c('pending_income_cents'),
      projectedBalanceCents: c('projected_balance_cents'),
    );
  }
}

class CategorySpending {
  const CategorySpending({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.totalCents,
    required this.count,
  });

  final String? categoryId;
  final String name;
  final String icon;
  final String color;
  final int totalCents;
  final int count;

  factory CategorySpending.fromJson(Map<String, dynamic> j) => CategorySpending(
    categoryId: j['category_id'] as String?,
    name: j['name'] as String,
    icon: j['icon'] as String? ?? 'category',
    color: j['color'] as String? ?? '#94A3B8',
    totalCents: (j['total_cents'] as num).toInt(),
    count: (j['tx_count'] as num?)?.toInt() ?? 0,
  );
}

class BudgetStatus {
  const BudgetStatus({
    required this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.limitCents,
    required this.spentCents,
  });

  final String budgetId;
  final String? categoryId; // null = orçamento mensal geral
  final String categoryName;
  final String icon;
  final String color;
  final int limitCents;
  final int spentCents;

  bool get isOverall => categoryId == null;

  factory BudgetStatus.fromJson(Map<String, dynamic> j) => BudgetStatus(
    budgetId: j['budget_id'] as String,
    categoryId: j['category_id'] as String?,
    categoryName: j['category_name'] as String,
    icon: j['icon'] as String? ?? 'category',
    color: j['color'] as String? ?? '#2563EB',
    limitCents: (j['limit_cents'] as num).toInt(),
    spentCents: (j['spent_cents'] as num).toInt(),
  );
}

class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.description,
    required this.frequency,
    required this.intervalCount,
    required this.startDate,
    this.endDate,
    this.active = true,
    this.categoryName,
    this.categoryId,
    this.categoryIcon,
    this.categoryColor,
    this.accountId,
    this.accountName,
    this.paymentMethod,
  });

  final String id;
  final TransactionType type;
  final int amountCents;
  final String description;
  final RecurrenceFrequency frequency;
  final int intervalCount;
  final DateTime startDate;
  final DateTime? endDate;
  final bool active;
  final String? categoryName;
  final String? categoryId;
  final String? categoryIcon;
  final String? categoryColor;
  final String? accountId;
  final String? accountName;
  final PaymentMethod? paymentMethod;

  /// Data da n-ésima ocorrência (mesma regra do banco: sempre a partir do início).
  DateTime occurrence(int n) => switch (frequency) {
    RecurrenceFrequency.weekly => startDate.add(Duration(days: 7 * intervalCount * n)),
    RecurrenceFrequency.yearly => Dates.addMonths(startDate, 12 * intervalCount * n),
    RecurrenceFrequency.monthly => Dates.addMonths(startDate, intervalCount * n),
  };

  /// Próxima ocorrência a partir de [from] (null se já terminou).
  DateTime? nextOccurrence(DateTime from) {
    for (var n = 0; n < 2000; n++) {
      final d = occurrence(n);
      if (endDate != null && d.isAfter(endDate!)) return null;
      if (!d.isBefore(Dates.dateOnly(from))) return d;
    }
    return null;
  }

  /// "Todo mês", "A cada 3 meses", "Toda semana"…
  String get everyLabel => switch (frequency) {
    RecurrenceFrequency.weekly => intervalCount == 1 ? 'Toda semana' : 'A cada $intervalCount semanas',
    RecurrenceFrequency.yearly => 'Todo ano',
    RecurrenceFrequency.monthly => intervalCount == 1 ? 'Todo mês' : 'A cada $intervalCount meses',
  };

  factory RecurringTransaction.fromJson(Map<String, dynamic> j) => RecurringTransaction(
    id: j['id'] as String,
    type: TransactionType.tryParse(j['type'] as String?) ?? TransactionType.expense,
    amountCents: (j['amount_cents'] as num).toInt(),
    description: j['description'] as String,
    frequency: RecurrenceFrequency.parse(j['frequency'] as String?),
    intervalCount: (j['interval_count'] as num?)?.toInt() ?? 1,
    startDate: Dates.parseIso(j['start_date'] as String),
    endDate: j['end_date'] == null ? null : Dates.parseIso(j['end_date'] as String),
    active: j['active'] as bool? ?? true,
    categoryName: (j['category'] as Map<String, dynamic>?)?['name'] as String?,
    categoryIcon: (j['category'] as Map<String, dynamic>?)?['icon'] as String?,
    categoryColor: (j['category'] as Map<String, dynamic>?)?['color'] as String?,
    categoryId: j['category_id'] as String?,
    accountId: j['account_id'] as String?,
    accountName: (j['account'] as Map<String, dynamic>?)?['name'] as String?,
    paymentMethod: PaymentMethod.tryParse(j['payment_method'] as String?),
  );
}

class FinancialGoal {
  const FinancialGoal({
    required this.id,
    required this.name,
    required this.targetCents,
    required this.currentCents,
    this.targetDate,
    this.icon = 'savings',
  });

  final String id;
  final String name;
  final int targetCents;
  final int currentCents;
  final DateTime? targetDate;
  final String icon;

  factory FinancialGoal.fromJson(Map<String, dynamic> j) => FinancialGoal(
    id: j['id'] as String,
    name: j['name'] as String,
    targetCents: (j['target_amount_cents'] as num).toInt(),
    currentCents: (j['current_amount_cents'] as num).toInt(),
    targetDate: j['target_date'] == null ? null : Dates.parseIso(j['target_date'] as String),
    icon: j['icon'] as String? ?? 'savings',
  );
}

class Insight {
  const Insight({
    required this.kind,
    required this.severity,
    required this.title,
    required this.body,
    required this.metrics,
  });

  final String kind;
  final String severity; // info | warning | positive
  final String title;
  final String body;
  final Map<String, dynamic> metrics;

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
    kind: j['kind'] as String,
    severity: j['severity'] as String? ?? 'info',
    title: j['title'] as String,
    body: j['body'] as String,
    metrics: (j['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}
