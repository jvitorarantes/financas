import '../../core/dates.dart';
import '../../core/money.dart';
import 'enums.dart';

/// Recorrência escolhida no formulário.
class RecurrenceDraft {
  const RecurrenceDraft({this.frequency = RecurrenceFrequency.monthly, this.intervalCount = 1, this.endDate});
  final RecurrenceFrequency frequency;
  final int intervalCount;
  final DateTime? endDate;

  Map<String, dynamic> toJson() => {
    'frequency': frequency.value,
    'interval_count': intervalCount,
    if (endDate != null) 'end_date': Dates.iso(endDate!),
  };
}

/// Estado editável de uma movimentação antes de salvar (formulário manual e
/// tela de confirmação do áudio usam o mesmo modelo e as mesmas validações).
class TransactionDraft {
  const TransactionDraft({
    required this.idempotencyKey,
    required this.date,
    this.type,
    this.amountCents,
    this.description = '',
    this.categoryId,
    this.accountId,
    this.destinationAccountId,
    this.paymentMethod,
    this.notes = '',
    this.alreadyPaid,
    this.installments,
    this.recurrence,
    this.source = TransactionSource.manual,
    this.transcription,
    this.audioSessionId,
  });

  /// Gerada uma única vez por formulário/sessão de áudio: salvar duas vezes
  /// com a mesma chave não cria dois lançamentos.
  final String idempotencyKey;
  final TransactionType? type;
  final int? amountCents;
  final String description;
  final String? categoryId;
  final String? accountId;
  final String? destinationAccountId;
  final DateTime date;
  final PaymentMethod? paymentMethod;
  final String notes;

  /// null = automático (pago se a data já chegou).
  final bool? alreadyPaid;
  final int? installments;
  final RecurrenceDraft? recurrence;
  final TransactionSource source;
  final String? transcription;
  final String? audioSessionId;

  bool get isTransfer => type == TransactionType.transfer;
  bool get isFuture => Dates.dateOnly(date).isAfter(Dates.today());

  /// Parcelas calculadas (centavos). Vazio se não for parcelado.
  List<int> get installmentAmounts =>
      (installments ?? 1) > 1 && amountCents != null ? Money.splitInstallments(amountCents!, installments!) : const [];

  TransactionDraft copyWith({
    TransactionType? type,
    int? amountCents,
    String? description,
    String? categoryId,
    String? accountId,
    String? destinationAccountId,
    DateTime? date,
    PaymentMethod? paymentMethod,
    String? notes,
    bool? alreadyPaid,
    int? installments,
    RecurrenceDraft? recurrence,
    bool clearCategory = false,
    bool clearDestination = false,
    bool clearPaymentMethod = false,
    bool clearInstallments = false,
    bool clearRecurrence = false,
    bool clearAmount = false,
    bool clearAlreadyPaid = false,
  }) {
    return TransactionDraft(
      idempotencyKey: idempotencyKey,
      type: type ?? this.type,
      amountCents: clearAmount ? null : amountCents ?? this.amountCents,
      description: description ?? this.description,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      destinationAccountId: clearDestination ? null : destinationAccountId ?? this.destinationAccountId,
      date: date ?? this.date,
      paymentMethod: clearPaymentMethod ? null : paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      alreadyPaid: clearAlreadyPaid ? null : alreadyPaid ?? this.alreadyPaid,
      installments: clearInstallments ? null : installments ?? this.installments,
      recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
      source: source,
      transcription: transcription,
      audioSessionId: audioSessionId,
    );
  }

  /// Erros de validação por campo (vazio = pode salvar).
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (type == null) errors['type'] = 'Escolha o tipo da movimentação.';
    final amount = amountCents;
    if (amount == null || amount <= 0) {
      errors['amount'] = 'Informe um valor maior que zero.';
    } else if (amount > Money.maxCents) {
      errors['amount'] = 'Valor acima do limite permitido.';
    }
    final desc = description.trim();
    if (desc.isEmpty) {
      errors['description'] = 'Informe uma descrição.';
    } else if (desc.length > 120) {
      errors['description'] = 'Use no máximo 120 caracteres.';
    }
    if (accountId == null) errors['account'] = 'Escolha uma conta.';
    if (isTransfer) {
      if (destinationAccountId == null) {
        errors['destination'] = 'Escolha a conta de destino.';
      } else if (destinationAccountId == accountId) {
        errors['destination'] = 'A conta de destino deve ser diferente da de origem.';
      }
      if ((installments ?? 1) > 1 || recurrence != null) {
        errors['repeat'] = 'Transferências não podem ser parceladas nem recorrentes.';
      }
    }
    final n = installments;
    if (n != null && n != 1) {
      if (n < 2 || n > 120) errors['installments'] = 'O número de parcelas deve ser entre 2 e 120.';
      if (type != null && type != TransactionType.expense) {
        errors['installments'] = 'Só despesas podem ser parceladas.';
      }
      if (recurrence != null) errors['repeat'] = 'Escolha parcelado ou recorrente, não os dois.';
    }
    if (alreadyPaid == true && isFuture) {
      errors['status'] = 'Uma movimentação com data futura ainda não pode estar paga.';
    }
    if (notes.length > 500) errors['notes'] = 'Use no máximo 500 caracteres.';
    final minDate = DateTime(2000);
    final maxDate = DateTime(2100, 12, 31);
    if (date.isBefore(minDate) || date.isAfter(maxDate)) errors['date'] = 'Data inválida.';
    return errors;
  }

  bool get isValid => validate().isEmpty;

  /// Corpo enviado para `public.create_transaction`.
  Map<String, dynamic> toPayload() {
    final errors = validate();
    if (errors.isNotEmpty) throw StateError('draft inválido: ${errors.keys.join(', ')}');
    final paid = alreadyPaid;
    return {
      'idempotency_key': idempotencyKey,
      'type': type!.value,
      'amount_cents': amountCents,
      'description': description.trim(),
      'category_id': isTransfer ? null : categoryId,
      'account_id': accountId,
      'destination_account_id': isTransfer ? destinationAccountId : null,
      'transaction_date': Dates.iso(date),
      'payment_method': isTransfer ? null : paymentMethod?.value,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      if (paid != null) 'status': paid ? 'paid' : 'pending',
      if ((installments ?? 1) > 1) 'installments': installments,
      if (recurrence != null) 'recurring': recurrence!.toJson(),
      'source': source == TransactionSource.audio ? 'audio' : 'manual',
      if (source == TransactionSource.audio) 'transcription': transcription,
      if (source == TransactionSource.audio) 'audio_session_id': audioSessionId,
    };
  }
}
