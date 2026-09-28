import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/finance_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../domain/models/account.dart';
import '../domain/models/category.dart';
import '../domain/models/summaries.dart';
import '../domain/models/transaction.dart';

/// Incrementado sempre que uma movimentação muda: todos os dados financeiros
/// observam este contador e recarregam (dashboard atualiza após salvar).
class FinanceRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final financeRevisionProvider = NotifierProvider<FinanceRevision, int>(FinanceRevision.new);

/// Mês selecionado no dashboard/orçamento/análises.
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() => Dates.firstOfMonth(Dates.today());
  void previous() => state = DateTime(state.year, state.month - 1);
  void next() => state = DateTime(state.year, state.month + 1);
  void set(DateTime month) => state = Dates.firstOfMonth(month);
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

final accountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(catalogRepositoryProvider).accounts();
});

final activeAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final all = await ref.watch(accountsProvider.future);
  return all.where((a) => !a.archived).toList();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(catalogRepositoryProvider).categories();
});

/// Garante que as recorrências já tenham os lançamentos previstos até o fim
/// do mês informado (ex.: ao abrir o mês que vem, o aluguel do dia 10 já
/// aparece como previsto). Só age para meses futuros; o banco limita a ~1 ano.
final recurringUntilProvider = FutureProvider.family<void, DateTime>((ref, monthEnd) async {
  ref.watch(financeRevisionProvider);
  if (!monthEnd.isAfter(Dates.addMonths(Dates.today(), 2))) return;
  try {
    await ref.watch(transactionsRepositoryProvider).materializeRecurring(until: monthEnd);
  } catch (_) {
    // Não impede a tela de abrir; os lançamentos já existentes continuam visíveis.
  }
});

final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  ref.watch(financeRevisionProvider);
  final month = ref.watch(selectedMonthProvider);
  await ref.watch(recurringUntilProvider(Dates.lastOfMonth(month)).future);
  return ref.watch(financeRepositoryProvider).summary(month);
});

final spendingByCategoryProvider = FutureProvider<List<CategorySpending>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).spendingByCategory(ref.watch(selectedMonthProvider));
});

final budgetStatusProvider = FutureProvider<List<BudgetStatus>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(financeRepositoryProvider).budgetStatus(ref.watch(selectedMonthProvider));
});

final recentTransactionsProvider = FutureProvider<List<FinanceTransaction>>((ref) {
  ref.watch(financeRevisionProvider);
  return ref.watch(transactionsRepositoryProvider).recent(limit: 6);
});
