import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/transaction_draft.dart';

TransactionDraft draft({
  TransactionType? type = TransactionType.expense,
  int? amount = 4590,
  String description = 'Almoço',
  String? account = 'acc-cc',
  String? destination,
  DateTime? date,
}) => TransactionDraft(
  idempotencyKey: '00000000-0000-4000-8000-000000000001',
  type: type,
  amountCents: amount,
  description: description,
  categoryId: 'cat-alim',
  accountId: account,
  destinationAccountId: destination,
  date: date ?? Dates.today(),
);

void main() {
  group('criação de despesa e receita', () {
    test('despesa válida gera o payload do banco', () {
      final p = draft().copyWith(paymentMethod: PaymentMethod.pix).toPayload();
      expect(p['type'], 'expense');
      expect(p['amount_cents'], 4590);
      expect(p['description'], 'Almoço');
      expect(p['category_id'], 'cat-alim');
      expect(p['payment_method'], 'pix');
      expect(p['source'], 'manual');
      expect(p['idempotency_key'], isNotEmpty);
      expect(p.containsKey('installments'), isFalse);
    });

    test('receita válida', () {
      final p = draft(type: TransactionType.income, amount: 320000, description: 'Salário').toPayload();
      expect(p['type'], 'income');
      expect(p['amount_cents'], 320000);
    });

    test('exige tipo, valor, descrição e conta', () {
      final errors = draft(type: null, amount: null, description: '  ', account: null).validate();
      expect(errors.keys, containsAll(['type', 'amount', 'description', 'account']));
      expect(() => draft(amount: null).toPayload(), throwsStateError);
    });

    test('valor zero, negativo ou acima do limite é recusado', () {
      expect(draft(amount: 0).validate().keys, contains('amount'));
      expect(draft(amount: -100).validate().keys, contains('amount'));
      expect(draft(amount: 100000000001).validate().keys, contains('amount'));
      expect(draft(amount: 1).validate(), isEmpty);
    });
  });

  group('transferência', () {
    test('não leva categoria nem forma de pagamento', () {
      final p = draft(
        type: TransactionType.transfer,
        destination: 'acc-poup',
      ).copyWith(paymentMethod: PaymentMethod.pix).toPayload();
      expect(p['type'], 'transfer');
      expect(p['category_id'], isNull);
      expect(p['payment_method'], isNull);
      expect(p['destination_account_id'], 'acc-poup');
    });

    test('exige destino diferente da origem', () {
      expect(draft(type: TransactionType.transfer).validate().keys, contains('destination'));
      expect(draft(type: TransactionType.transfer, destination: 'acc-cc').validate().keys, contains('destination'));
    });

    test('não pode ser parcelada nem recorrente', () {
      final d = draft(type: TransactionType.transfer, destination: 'acc-poup');
      expect(d.copyWith(installments: 3).validate().keys, contains('repeat'));
      expect(d.copyWith(recurrence: const RecurrenceDraft()).validate().keys, contains('repeat'));
    });
  });

  group('parcelamento e recorrência', () {
    test('parcelado envia número de parcelas e calcula os valores', () {
      final d = draft(amount: 240000, description: 'Televisão').copyWith(installments: 12);
      expect(d.installmentAmounts, List.filled(12, 20000));
      expect(d.toPayload()['installments'], 12);
    });

    test('só despesas podem ser parceladas, entre 2 e 120', () {
      expect(draft(type: TransactionType.income).copyWith(installments: 3).validate().keys, contains('installments'));
      expect(draft().copyWith(installments: 121).validate().keys, contains('installments'));
    });

    test('parcelado e recorrente ao mesmo tempo é recusado', () {
      final d = draft().copyWith(installments: 3, recurrence: const RecurrenceDraft());
      expect(d.validate().keys, contains('repeat'));
    });

    test('recorrência vai no payload', () {
      final end = DateTime(2027, 12, 31);
      final p = draft()
          .copyWith(
            recurrence: RecurrenceDraft(frequency: RecurrenceFrequency.monthly, endDate: end),
          )
          .toPayload();
      expect(p['recurring'], {'frequency': 'monthly', 'interval_count': 1, 'end_date': '2027-12-31'});
    });
  });

  group('status', () {
    test('data futura não pode estar paga (regra 5)', () {
      final future = Dates.today().add(const Duration(days: 3));
      expect(draft(date: future).copyWith(alreadyPaid: true).validate().keys, contains('status'));
      expect(draft(date: future).validate(), isEmpty);
      expect(draft(date: future).toPayload().containsKey('status'), isFalse, reason: 'o banco define pendente');
    });

    test('pendente explícito', () {
      expect(draft().copyWith(alreadyPaid: false).toPayload()['status'], 'pending');
    });
  });

  test('origem áudio leva transcrição e sessão', () {
    final d = TransactionDraft(
      idempotencyKey: 'sess-1',
      type: TransactionType.expense,
      amountCents: 8500,
      description: 'Gasolina',
      accountId: 'acc-cc',
      date: Dates.today(),
      source: TransactionSource.audio,
      transcription: 'Gastei 85 reais de gasolina',
      audioSessionId: 'sess-1',
    );
    final p = d.toPayload();
    expect(p['source'], 'audio');
    expect(p['audio_session_id'], 'sess-1');
    expect(p['idempotency_key'], 'sess-1');
    expect(p['transcription'], 'Gastei 85 reais de gasolina');
  });
}
