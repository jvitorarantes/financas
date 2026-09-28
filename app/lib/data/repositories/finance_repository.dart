import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../domain/models/summaries.dart';
import '../supabase_providers.dart';

/// Leituras agregadas (dashboard e orçamento), orçamentos, recorrências e metas.
abstract interface class FinanceRepository {
  Future<DashboardSummary> summary(DateTime month);
  Future<List<CategorySpending>> spendingByCategory(DateTime month);
  Future<List<BudgetStatus>> budgetStatus(DateTime month);
  Future<void> saveBudget({String? categoryId, required int amountCents});
  Future<void> deleteBudget(String budgetId);
  Future<List<RecurringTransaction>> recurring();
  Future<void> setRecurringActive(String id, bool active);
  Future<List<FinancialGoal>> goals();
  Future<void> saveGoal({String? id, required String name, required int targetCents, DateTime? targetDate});
  Future<void> setGoalAmount(String id, int currentCents);
  Future<void> deleteGoal(String id);
}

class SupabaseFinanceRepository implements FinanceRepository {
  SupabaseFinanceRepository(this._db);
  final SupabaseClient _db;

  String get _uid => _db.auth.currentUser!.id;

  Future<T> _guard<T>(Future<T> Function() body, {AppFailure fallback = AppFailure.generic}) async {
    try {
      return await body();
    } catch (e) {
      throw toFailure(e, fallback: fallback);
    }
  }

  @override
  Future<DashboardSummary> summary(DateTime month) => _guard(() async {
    final res = await _db.rpc('dashboard_summary', params: {'p_month': Dates.iso(Dates.firstOfMonth(month))});
    return DashboardSummary.fromJson((res as Map).cast<String, dynamic>());
  });

  @override
  Future<List<CategorySpending>> spendingByCategory(DateTime month) => _guard(() async {
    final res = await _db.rpc('spending_by_category', params: {'p_month': Dates.iso(Dates.firstOfMonth(month))});
    return (res as List).map((e) => CategorySpending.fromJson((e as Map).cast<String, dynamic>())).toList();
  });

  @override
  Future<List<BudgetStatus>> budgetStatus(DateTime month) => _guard(() async {
    final res = await _db.rpc('budget_status', params: {'p_month': Dates.iso(Dates.firstOfMonth(month))});
    return (res as List).map((e) => BudgetStatus.fromJson((e as Map).cast<String, dynamic>())).toList();
  });

  @override
  Future<void> saveBudget({String? categoryId, required int amountCents}) => _guard(() async {
    // Orçamento padrão (vale para todos os meses): month = null.
    var existing = _db.from('budgets').select('id').isFilter('month', null);
    existing = categoryId == null ? existing.isFilter('category_id', null) : existing.eq('category_id', categoryId);
    final row = await existing.maybeSingle();
    if (row == null) {
      await _db.from('budgets').insert({'user_id': _uid, 'category_id': categoryId, 'amount_cents': amountCents});
    } else {
      await _db.from('budgets').update({'amount_cents': amountCents}).eq('id', row['id'] as String);
    }
  });

  @override
  Future<void> deleteBudget(String budgetId) => _guard(() => _db.from('budgets').delete().eq('id', budgetId));

  @override
  Future<List<RecurringTransaction>> recurring() => _guard(() async {
    final rows = await _db
        .from('recurring_transactions')
        .select('*, category:categories!recurring_transactions_user_id_category_id_fkey(name)')
        .order('active', ascending: false)
        .order('description');
    return rows.map(RecurringTransaction.fromJson).toList();
  });

  @override
  Future<void> setRecurringActive(String id, bool active) async {
    await _guard(() async {
      await _db
          .from('recurring_transactions')
          .update({
            'active': active,
            // Ao reativar, volta a gerar ocorrências a partir de hoje.
            if (active) 'generated_until': Dates.iso(Dates.today()),
          })
          .eq('id', id);
      if (!active) {
        // Ao encerrar, remove as ocorrências futuras ainda não pagas.
        await _db
            .from('transactions')
            .delete()
            .eq('recurring_transaction_id', id)
            .eq('status', 'pending')
            .gt('transaction_date', Dates.iso(Dates.today()));
      }
    });
  }

  @override
  Future<List<FinancialGoal>> goals() => _guard(() async {
    final rows = await _db.from('financial_goals').select().order('created_at');
    return rows.map(FinancialGoal.fromJson).toList();
  });

  @override
  Future<void> saveGoal({String? id, required String name, required int targetCents, DateTime? targetDate}) =>
      _guard(() async {
        final data = {
          'name': name.trim(),
          'target_amount_cents': targetCents,
          'target_date': targetDate == null ? null : Dates.iso(targetDate),
        };
        if (id == null) {
          await _db.from('financial_goals').insert({...data, 'user_id': _uid});
        } else {
          await _db.from('financial_goals').update(data).eq('id', id);
        }
      });

  @override
  Future<void> setGoalAmount(String id, int currentCents) => _guard(
    () =>
        _db.from('financial_goals').update({'current_amount_cents': currentCents < 0 ? 0 : currentCents}).eq('id', id),
  );

  @override
  Future<void> deleteGoal(String id) => _guard(() => _db.from('financial_goals').delete().eq('id', id));
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => SupabaseFinanceRepository(ref.watch(supabaseProvider)),
);
