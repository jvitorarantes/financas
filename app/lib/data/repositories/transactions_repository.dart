import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/transaction_draft.dart';
import '../supabase_providers.dart';

class TransactionFilter {
  const TransactionFilter({this.from, this.to, this.type, this.categoryId, this.accountId, this.search = ''});
  final DateTime? from;
  final DateTime? to;
  final TransactionType? type;
  final String? categoryId;
  final String? accountId;
  final String search;

  bool get hasFilters => type != null || categoryId != null || accountId != null || search.trim().isNotEmpty;

  TransactionFilter copyWith({
    DateTime? from,
    DateTime? to,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    String? search,
    bool clearType = false,
    bool clearCategory = false,
    bool clearAccount = false,
  }) => TransactionFilter(
    from: from ?? this.from,
    to: to ?? this.to,
    type: clearType ? null : type ?? this.type,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    accountId: clearAccount ? null : accountId ?? this.accountId,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.from == from &&
      other.to == to &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.search == search;

  @override
  int get hashCode => Object.hash(from, to, type, categoryId, accountId, search);
}

class CreateTransactionResult {
  const CreateTransactionResult({required this.transactionId, required this.created});
  final String? transactionId;

  /// false = a chave de idempotência já tinha sido usada (nada duplicado).
  final bool created;
}

abstract interface class TransactionsRepository {
  Future<CreateTransactionResult> create(TransactionDraft draft);
  Future<List<FinanceTransaction>> list(TransactionFilter filter, {int limit = 100, int offset = 0});
  Future<List<FinanceTransaction>> recent({int limit = 5});
  Future<List<FinanceTransaction>> pending({required DateTime until});
  Future<void> update(String id, TransactionDraft draft);
  Future<void> markPaid(String id, {DateTime? on});
  Future<void> delete(String id);
  Future<void> deleteInstallmentPlan(String installmentId);

  /// Gera as ocorrências previstas das recorrências até [until]
  /// (padrão: daqui a 2 meses). Idempotente.
  Future<int> materializeRecurring({DateTime? until});
}

class SupabaseTransactionsRepository implements TransactionsRepository {
  SupabaseTransactionsRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<CreateTransactionResult> create(TransactionDraft draft) async {
    try {
      final res = await _db.rpc('create_transaction', params: {'payload': draft.toPayload()});
      final map = (res as Map).cast<String, dynamic>();
      return CreateTransactionResult(
        transactionId: map['transaction_id'] as String?,
        created: map['created'] as bool? ?? true,
      );
    } catch (e) {
      throw toFailure(e, fallback: AppFailure.saveFailed);
    }
  }

  @override
  Future<List<FinanceTransaction>> list(TransactionFilter f, {int limit = 100, int offset = 0}) async {
    try {
      var q = _db.from('transactions').select(FinanceTransaction.select);
      if (f.from != null) q = q.gte('transaction_date', Dates.iso(f.from!));
      if (f.to != null) q = q.lte('transaction_date', Dates.iso(f.to!));
      if (f.type != null) q = q.eq('type', f.type!.value);
      if (f.categoryId != null) q = q.eq('category_id', f.categoryId!);
      if (f.accountId != null) {
        q = q.or('account_id.eq.${f.accountId},destination_account_id.eq.${f.accountId}');
      }
      final term = f.search.trim().replaceAll(RegExp(r'[%_,().*]'), ' ');
      if (term.isNotEmpty) q = q.ilike('description', '%$term%');
      final rows = await q
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(FinanceTransaction.fromJson).toList();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<List<FinanceTransaction>> recent({int limit = 5}) async {
    try {
      final rows = await _db
          .from('transactions')
          .select(FinanceTransaction.select)
          .eq('status', TransactionStatus.paid.value)
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(FinanceTransaction.fromJson).toList();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<List<FinanceTransaction>> pending({required DateTime until}) async {
    try {
      final rows = await _db
          .from('transactions')
          .select(FinanceTransaction.select)
          .eq('status', TransactionStatus.pending.value)
          .lte('transaction_date', Dates.iso(until))
          .order('transaction_date')
          .limit(500);
      return rows.map(FinanceTransaction.fromJson).toList();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<void> update(String id, TransactionDraft d) async {
    final errors = d.validate();
    if (errors.isNotEmpty) throw AppFailure(errors.values.first, code: 'validation');
    try {
      final paid = d.alreadyPaid ?? !d.isFuture;
      await _db
          .from('transactions')
          .update({
            'type': d.type!.value,
            'amount_cents': d.amountCents,
            'description': d.description.trim(),
            'category_id': d.isTransfer ? null : d.categoryId,
            'account_id': d.accountId,
            'destination_account_id': d.isTransfer ? d.destinationAccountId : null,
            'transaction_date': Dates.iso(d.date),
            'payment_method': d.isTransfer ? null : d.paymentMethod?.value,
            'notes': d.notes.trim().isEmpty ? null : d.notes.trim(),
            'status': (paid && !d.isFuture) ? 'paid' : 'pending',
          })
          .eq('id', id);
    } catch (e) {
      throw toFailure(e, fallback: AppFailure.saveFailed);
    }
  }

  @override
  Future<void> markPaid(String id, {DateTime? on}) async {
    try {
      final date = on ?? Dates.today();
      await _db.from('transactions').update({'status': 'paid', 'transaction_date': Dates.iso(date)}).eq('id', id);
    } catch (e) {
      throw toFailure(e, fallback: AppFailure.saveFailed);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _db.from('transactions').delete().eq('id', id);
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<void> deleteInstallmentPlan(String installmentId) async {
    try {
      await _db.from('installments').delete().eq('id', installmentId);
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<int> materializeRecurring({DateTime? until}) async {
    try {
      final limit = until ?? Dates.addMonths(Dates.today(), 2);
      final res = await _db.rpc('materialize_recurring', params: {'p_until': Dates.iso(limit)});
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      throw toFailure(e);
    }
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => SupabaseTransactionsRepository(ref.watch(supabaseProvider)),
);
