import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/extraction.dart';

import '../helpers/fakes.dart';

void main() {
  Map<String, dynamic> base(Map<String, dynamic> over) => {
    'type': 'expense',
    'amount_cents': 8500,
    'description': 'Gasolina',
    'category': 'Transporte',
    'date': '2026-09-28',
    'payment_method': 'credit_card',
    'confidence': 0.9,
    'missing_fields': [],
    'requires_clarification': false,
    'questions': [],
    ...over,
  };

  test('interpreta a resposta e liga nomes aos cadastros', () {
    final e = TransactionExtraction.fromJson(base({}));
    final d = e.toDraft(sessionId: 's1', transcription: 't', categories: testCategories, accounts: testAccounts);
    expect(d.type, TransactionType.expense);
    expect(d.amountCents, 8500);
    expect(d.categoryId, 'cat-transp');
    expect(d.accountId, 'acc-cc', reason: 'sem conta dita, usa a conta corrente');
    expect(d.paymentMethod, PaymentMethod.creditCard);
    expect(d.date, DateTime(2026, 9, 28));
    expect(d.source, TransactionSource.audio);
    expect(d.idempotencyKey, 's1');
  });

  test('categoria sem acento e em minúsculas ainda casa', () {
    final e = TransactionExtraction.fromJson(base({'category': 'alimentacao'}));
    final d = e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts);
    expect(d.categoryId, 'cat-alim');
  });

  test('categoria inexistente fica vazia para o usuário escolher', () {
    final e = TransactionExtraction.fromJson(base({'category': 'Pets'}));
    expect(
      e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts).categoryId,
      isNull,
    );
  });

  test('transferência liga origem e destino e não tem categoria', () {
    final e = TransactionExtraction.fromJson(
      base({
        'type': 'transfer',
        'amount_cents': 20000,
        'category': null,
        'account': 'Conta corrente',
        'destination_account': 'Poupança',
        'payment_method': null,
      }),
    );
    final d = e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts);
    expect(d.type, TransactionType.transfer);
    expect(d.accountId, 'acc-cc');
    expect(d.destinationAccountId, 'acc-poup');
    expect(d.categoryId, isNull);
    expect(d.isValid, isTrue);
  });

  test('pagamento em dinheiro usa a carteira', () {
    final e = TransactionExtraction.fromJson(base({'payment_method': 'cash'}));
    expect(
      e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts).accountId,
      'acc-cart',
    );
  });

  test('valor ausente continua ausente (nunca inventado)', () {
    final e = TransactionExtraction.fromJson(
      base({
        'amount_cents': null,
        'requires_clarification': true,
        'missing_fields': ['amount'],
        'questions': ['Qual foi o valor?'],
      }),
    );
    final d = e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts);
    expect(d.amountCents, isNull);
    expect(d.isValid, isFalse);
    expect(e.questions, ['Qual foi o valor?']);
  });

  test('parcelas vêm da extração', () {
    final e = TransactionExtraction.fromJson(
      base({'amount_cents': 240000, 'installments': 12, 'installment_amount_cents': 20000}),
    );
    final d = e.toDraft(sessionId: 's', transcription: 't', categories: testCategories, accounts: testAccounts);
    expect(d.installments, 12);
    expect(d.installmentAmounts.first, 20000);
  });

  test('data inválida vira hoje', () {
    final e = TransactionExtraction.fromJson(base({'date': 'ontem'}));
    expect(e.date, Dates.today());
  });
}
