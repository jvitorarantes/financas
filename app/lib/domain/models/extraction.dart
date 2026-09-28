import '../../core/dates.dart';
import 'account.dart';
import 'category.dart';
import 'enums.dart';
import 'transaction_draft.dart';

/// Resultado conferido da interpretação por IA (edge function extract-transaction).
class TransactionExtraction {
  const TransactionExtraction({
    required this.date,
    this.type,
    this.amountCents,
    this.description,
    this.category,
    this.account,
    this.destinationAccount,
    this.paymentMethod,
    this.installments,
    this.installmentAmountCents,
    this.recurring = false,
    this.notes = '',
    this.confidence = 0,
    this.missingFields = const [],
    this.requiresClarification = false,
    this.questions = const [],
  });

  final TransactionType? type;
  final int? amountCents;
  final String? description;
  final String? category;
  final DateTime date;
  final String? account;
  final String? destinationAccount;
  final PaymentMethod? paymentMethod;
  final int? installments;
  final int? installmentAmountCents;
  final bool recurring;
  final String notes;
  final double confidence;
  final List<String> missingFields;
  final bool requiresClarification;
  final List<String> questions;

  factory TransactionExtraction.fromJson(Map<String, dynamic> j) {
    DateTime date;
    try {
      date = Dates.parseIso(j['date'] as String);
    } catch (_) {
      date = Dates.today();
    }
    return TransactionExtraction(
      type: TransactionType.tryParse(j['type'] as String?),
      amountCents: (j['amount_cents'] as num?)?.toInt(),
      description: j['description'] as String?,
      category: j['category'] as String?,
      date: date,
      account: j['account'] as String?,
      destinationAccount: j['destination_account'] as String?,
      paymentMethod: PaymentMethod.tryParse(j['payment_method'] as String?),
      installments: (j['installments'] as num?)?.toInt(),
      installmentAmountCents: (j['installment_amount_cents'] as num?)?.toInt(),
      recurring: j['recurring'] as bool? ?? false,
      notes: j['notes'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      missingFields: ((j['missing_fields'] as List?) ?? const []).map((e) => e.toString()).toList(),
      requiresClarification: j['requires_clarification'] as bool? ?? false,
      questions: ((j['questions'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  /// Converte em rascunho editável, ligando nomes a IDs do cadastro.
  TransactionDraft toDraft({
    required String sessionId,
    required String transcription,
    required List<Category> categories,
    required List<Account> accounts,
  }) {
    String fold(String s) => s
        .toLowerCase()
        .replaceAll(RegExp('[áàâã]'), 'a')
        .replaceAll(RegExp('[éê]'), 'e')
        .replaceAll('í', 'i')
        .replaceAll(RegExp('[óôõ]'), 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .trim();
    Account? accountNamed(String? name) =>
        name == null ? null : accounts.where((a) => fold(a.name) == fold(name)).firstOrNull;

    final kind = type == TransactionType.income ? CategoryKind.income : CategoryKind.expense;
    final categoryName = category;
    final matchedCategory = categoryName == null
        ? null
        : categories.where((c) => c.kind == kind && fold(c.name) == fold(categoryName)).firstOrNull;

    final active = accounts.where((a) => !a.archived).toList();
    var origin = accountNamed(account);
    origin ??= paymentMethod == PaymentMethod.cash ? active.where((a) => a.type == AccountType.cash).firstOrNull : null;
    origin ??= active.where((a) => a.type == AccountType.checking).firstOrNull ?? active.firstOrNull;
    final destination = accountNamed(destinationAccount);

    return TransactionDraft(
      idempotencyKey: sessionId,
      type: type,
      amountCents: amountCents,
      description: description ?? '',
      categoryId: type == TransactionType.transfer ? null : matchedCategory?.id,
      accountId: origin?.id,
      destinationAccountId: type == TransactionType.transfer ? destination?.id : null,
      date: date,
      paymentMethod: type == TransactionType.transfer ? null : paymentMethod,
      notes: notes,
      installments: installments,
      recurrence: recurring ? const RecurrenceDraft() : null,
      source: TransactionSource.audio,
      transcription: transcription,
      audioSessionId: sessionId,
    );
  }
}
