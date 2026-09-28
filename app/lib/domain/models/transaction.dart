import '../../core/dates.dart';
import 'enums.dart';

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amountCents,
    required this.description,
    required this.date,
    required this.accountId,
    this.categoryId,
    this.destinationAccountId,
    this.paymentMethod,
    this.notes,
    this.source = TransactionSource.manual,
    this.transcription,
    this.recurringTransactionId,
    this.installmentId,
    this.installmentNumber,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.accountName,
    this.destinationAccountName,
  });

  final String id;
  final TransactionType type;
  final TransactionStatus status;
  final int amountCents;
  final String description;
  final DateTime date;
  final String accountId;
  final String? categoryId;
  final String? destinationAccountId;
  final PaymentMethod? paymentMethod;
  final String? notes;
  final TransactionSource source;
  final String? transcription;
  final String? recurringTransactionId;
  final String? installmentId;
  final int? installmentNumber;

  // Dados de junção para exibição.
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  final String? accountName;
  final String? destinationAccountName;

  bool get isPending => status == TransactionStatus.pending;

  /// Efeito no saldo total: transferência entre contas próprias soma zero.
  int get signedCents => switch (type) {
    TransactionType.income => amountCents,
    TransactionType.expense => -amountCents,
    TransactionType.transfer => 0,
  };

  /// Seleção usada nas consultas (com junções).
  static const select =
      '*, category:categories!transactions_user_id_category_id_fkey(name, icon, color), account:accounts!transactions_user_id_account_id_fkey(name), '
      'destination:accounts!transactions_user_id_destination_account_id_fkey(name)';

  factory FinanceTransaction.fromJson(Map<String, dynamic> j) {
    final category = j['category'] as Map<String, dynamic>?;
    return FinanceTransaction(
      id: j['id'] as String,
      type: TransactionType.tryParse(j['type'] as String?) ?? TransactionType.expense,
      status: TransactionStatus.parse(j['status'] as String?),
      amountCents: (j['amount_cents'] as num).toInt(),
      description: j['description'] as String,
      date: Dates.parseIso(j['transaction_date'] as String),
      accountId: j['account_id'] as String,
      categoryId: j['category_id'] as String?,
      destinationAccountId: j['destination_account_id'] as String?,
      paymentMethod: PaymentMethod.tryParse(j['payment_method'] as String?),
      notes: j['notes'] as String?,
      source: TransactionSource.parse(j['source'] as String?),
      transcription: j['transcription'] as String?,
      recurringTransactionId: j['recurring_transaction_id'] as String?,
      installmentId: j['installment_id'] as String?,
      installmentNumber: (j['installment_number'] as num?)?.toInt(),
      categoryName: category?['name'] as String?,
      categoryIcon: category?['icon'] as String?,
      categoryColor: category?['color'] as String?,
      accountName: (j['account'] as Map<String, dynamic>?)?['name'] as String?,
      destinationAccountName: (j['destination'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}
