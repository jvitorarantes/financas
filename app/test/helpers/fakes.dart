import 'dart:async';
import 'dart:typed_data';

import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/core/failure.dart';
import 'package:meu_financeiro/data/repositories/ai_repository.dart';
import 'package:meu_financeiro/data/repositories/auth_repository.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/finance_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/account.dart';
import 'package:meu_financeiro/domain/models/category.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/extraction.dart';
import 'package:meu_financeiro/domain/models/summaries.dart';
import 'package:meu_financeiro/domain/models/transaction.dart';
import 'package:meu_financeiro/domain/models/transaction_draft.dart';
import 'package:meu_financeiro/features/audio/audio_recorder.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

const testAccounts = [
  Account(id: 'acc-cc', name: 'Conta corrente', type: AccountType.checking),
  Account(id: 'acc-poup', name: 'Poupança', type: AccountType.savings),
  Account(id: 'acc-cart', name: 'Carteira', type: AccountType.cash),
];

const testCategories = [
  Category(id: 'cat-alim', name: 'Alimentação', kind: CategoryKind.expense, icon: 'restaurant'),
  Category(id: 'cat-transp', name: 'Transporte', kind: CategoryKind.expense, icon: 'directions_car'),
  Category(id: 'cat-compras', name: 'Compras', kind: CategoryKind.expense, icon: 'shopping_bag'),
  Category(id: 'cat-contas', name: 'Contas', kind: CategoryKind.expense, icon: 'receipt_long'),
  Category(id: 'cat-sal', name: 'Salário', kind: CategoryKind.income, icon: 'work'),
];

class FakeAuthRepository implements AuthRepository {
  final _events = StreamController<AuthChangeEvent>.broadcast();
  bool signedIn = false;
  Object? signInError;
  bool signUpNeedsConfirmation = true;
  Object? signUpError;
  bool setup = false;

  @override
  Future<bool> needsSetup() async => setup;
  final calls = <String>[];

  @override
  Stream<AuthChangeEvent> get events => _events.stream;
  @override
  bool get isSignedIn => signedIn;
  @override
  String? get email => signedIn ? 'ana@teste.com' : null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInError != null) throw signInError!;
    signedIn = true;
    _events.add(AuthChangeEvent.signedIn);
  }

  @override
  Future<bool> signUp({required String name, required String email, required String password}) async {
    calls.add('signUp:$name:$email');
    if (signUpError != null) throw signUpError!;
    return signUpNeedsConfirmation;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    signedIn = false;
    _events.add(AuthChangeEvent.signedOut);
  }

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');
  @override
  Future<void> updatePassword(String newPassword) async => calls.add('updatePassword');
}

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<Account>> accounts() async => [...accountList];
  List<Account> accountList = [...testAccounts];
  @override
  Future<List<Category>> categories() async => [...categoryList];
  List<Category> categoryList = [...testCategories];
  @override
  Future<void> archiveAccount(String id, {bool archived = true}) async {}
  @override
  Future<void> archiveCategory(String id, {bool archived = true}) async {}
  @override
  Future<String?> profileName() async => 'Ana';
  bool admin = false;
  @override
  Future<bool> isAdmin() async => admin;
  @override
  Future<void> saveAccount({
    String? id,
    required String name,
    required AccountType type,
    required int initialBalanceCents,
    required bool includeInBalance,
  }) async {}
  @override
  Future<void> saveCategory({
    String? id,
    required String name,
    required CategoryKind kind,
    required String icon,
    required String color,
  }) async {}
  @override
  Future<void> updateProfileName(String name) async {}
}

/// Simula o create_transaction do banco, inclusive a idempotência.
class FakeTransactionsRepository implements TransactionsRepository {
  final createdByKey = <String, TransactionDraft>{};
  int createCalls = 0;
  Object? createError;
  Completer<void>? gate;

  @override
  Future<CreateTransactionResult> create(TransactionDraft draft) async {
    createCalls++;
    draft.toPayload(); // mesma validação do app antes de enviar
    if (gate != null) await gate!.future;
    if (createError != null) throw createError!;
    final existed = createdByKey.containsKey(draft.idempotencyKey);
    createdByKey.putIfAbsent(draft.idempotencyKey, () => draft);
    return CreateTransactionResult(transactionId: 'tx-${draft.idempotencyKey}', created: !existed);
  }

  List<FinanceTransaction> listResult = const [];
  final listFilters = <TransactionFilter>[];
  @override
  Future<List<FinanceTransaction>> list(TransactionFilter filter, {int limit = 100, int offset = 0}) async {
    listFilters.add(filter);
    return listResult
        .where(
          (t) =>
              (filter.from == null || !t.date.isBefore(filter.from!)) &&
              (filter.to == null || !t.date.isAfter(filter.to!)),
        )
        .toList();
  }

  @override
  Future<List<FinanceTransaction>> recent({int limit = 5}) async => const [];
  @override
  Future<List<FinanceTransaction>> pending({required DateTime until}) async => const [];
  @override
  Future<void> update(String id, TransactionDraft draft) async {}
  @override
  Future<void> markPaid(String id, {DateTime? on}) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> deleteInstallmentPlan(String installmentId) async {}
  final materializedUntil = <DateTime>[];
  @override
  Future<int> materializeRecurring({DateTime? until}) async {
    if (until != null) materializedUntil.add(until);
    return 0;
  }
}

class FakeFinanceRepository implements FinanceRepository {
  DashboardSummary summaryValue = DashboardSummary(
    month: Dates.firstOfMonth(Dates.today()),
    currentBalanceCents: 0,
    monthIncomeCents: 0,
    monthExpenseCents: 0,
    pendingExpenseCents: 0,
    pendingIncomeCents: 0,
    projectedBalanceCents: 0,
  );
  @override
  Future<DashboardSummary> summary(DateTime month) async => summaryValue;
  @override
  Future<List<CategorySpending>> spendingByCategory(DateTime month) async => const [];
  @override
  Future<List<BudgetStatus>> budgetStatus(DateTime month) async => const [];
  @override
  Future<void> saveBudget({String? categoryId, required int amountCents}) async {}
  @override
  Future<void> deleteBudget(String budgetId) async {}
  @override
  Future<List<RecurringTransaction>> recurring() async => const [];
  @override
  Future<void> setRecurringActive(String id, bool active) async {}
  @override
  Future<List<FinancialGoal>> goals() async => const [];
  @override
  Future<void> saveGoal({String? id, required String name, required int targetCents, DateTime? targetDate}) async {}
  @override
  Future<void> setGoalAmount(String id, int currentCents) async {}
  @override
  Future<void> deleteGoal(String id) async {}
}

class FakeAiRepository implements AiRepository {
  String transcription = 'Gastei 85 reais de gasolina hoje no cartão.';
  Map<String, dynamic> extraction = {
    'type': 'expense',
    'amount': 85,
    'amount_cents': 8500,
    'description': 'Gasolina',
    'category': 'Transporte',
    'date': Dates.iso(Dates.today()),
    'account': null,
    'payment_method': 'credit_card',
    'installments': null,
    'recurring': false,
    'notes': '',
    'confidence': 0.95,
    'missing_fields': <String>[],
    'requires_clarification': false,
    'questions': <String>[],
  };
  Object? transcribeError;
  Object? extractError;
  Completer<void>? transcribeGate;
  final calls = <String>[];

  @override
  Future<String> transcribe({
    required String sessionId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
    void Function()? onUploaded,
  }) async {
    calls.add('transcribe:$sessionId:$durationMs');
    onUploaded?.call();
    if (transcribeGate != null) await transcribeGate!.future;
    if (transcribeError != null) throw transcribeError!;
    return transcription;
  }

  @override
  Future<ExtractionResponse> extract(String sessionId) async {
    calls.add('extract:$sessionId');
    if (extractError != null) throw extractError!;
    return ExtractionResponse(transcription: transcription, extraction: TransactionExtraction.fromJson(extraction));
  }

  @override
  Future<ExtractionResponse> extractText(String text) => extract('text');

  @override
  Future<void> cancelSession(String sessionId) async => calls.add('cancel:$sessionId');

  @override
  Future<List<Insight>> insights(DateTime month) async => const [];
  @override
  Future<List<Insight>> savedInsights(DateTime month) async => const [];
}

class FakeRecorder implements AudioRecorderService {
  bool permission = true;
  bool recording = false;
  final calls = <String>[];

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<void> start() async {
    calls.add('start');
    recording = true;
  }

  @override
  Future<RecordedAudio?> stop(Duration duration) async {
    calls.add('stop');
    recording = false;
    return RecordedAudio(
      bytes: Uint8List.fromList(List.filled(1000, 1)),
      fileName: 'audio.m4a',
      mimeType: 'audio/mp4',
      duration: duration,
      playbackPath: '/tmp/audio.m4a',
    );
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    recording = false;
  }

  @override
  Future<void> discard(RecordedAudio audio) async => calls.add('discard');

  @override
  Future<void> dispose() async {}
}

const networkError = AppFailure('Verifique sua conexão com a internet.', code: 'network');
