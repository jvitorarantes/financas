import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/features/transactions/transaction_form_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  late FakeTransactionsRepository transactions;
  setUp(() => transactions = FakeTransactionsRepository());

  Future<void> pumpForm(WidgetTester tester, String type) =>
      pumpRoutes(
        tester,
        initial: '/home',
        overrides: [
          transactionsRepositoryProvider.overrideWithValue(transactions),
          catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        ],
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: TextButton(onPressed: () => context.push('/new'), child: const Text('abrir')),
            ),
          ),
          GoRoute(
            path: '/new',
            builder: (_, _) => TransactionFormPage(initialType: TransactionType.tryParse(type)!),
          ),
        ],
      ).then((_) async {
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
      });

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byKey(const Key('save-transaction'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
  }

  testWidgets('valida antes de salvar', (tester) async {
    await pumpForm(tester, 'expense');
    await tapSave(tester);
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
    expect(find.text('Informe uma descrição.'), findsOneWidget);
    expect(transactions.createCalls, 0);
  });

  testWidgets('cria despesa e volta', (tester) async {
    await pumpForm(tester, 'expense');
    await tester.enterText(find.byKey(const Key('field-amount')), '4590');
    await tester.pump();
    expect(find.text('45,90'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-description')), 'Almoço');
    await tester.tap(find.text('Alimentação'));
    await tester.pump();
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(transactions.createCalls, 1);
    final saved = transactions.createdByKey.values.single;
    expect(saved.type, TransactionType.expense);
    expect(saved.amountCents, 4590);
    expect(saved.categoryId, 'cat-alim');
    expect(saved.accountId, 'acc-cc', reason: 'conta corrente é a padrão');
    expect(find.text('abrir'), findsOneWidget, reason: 'voltou após salvar');
  });

  testWidgets('cria receita', (tester) async {
    await pumpForm(tester, 'income');
    await tester.enterText(find.byKey(const Key('field-amount')), '320000');
    await tester.enterText(find.byKey(const Key('field-description')), 'Salário');
    await tapSave(tester);
    await tester.pumpAndSettle();
    final saved = transactions.createdByKey.values.single;
    expect(saved.type, TransactionType.income);
    expect(saved.amountCents, 320000);
  });

  testWidgets('duplo toque em salvar não duplica', (tester) async {
    transactions.gate = Completer<void>();
    await pumpForm(tester, 'expense');
    await tester.enterText(find.byKey(const Key('field-amount')), '1000');
    await tester.enterText(find.byKey(const Key('field-description')), 'Café');
    await tapSave(tester);
    await tapSave(tester);
    transactions.gate!.complete();
    await tester.pumpAndSettle();
    expect(transactions.createCalls, 1);
  });

  testWidgets('transferência exige conta de destino', (tester) async {
    await pumpForm(tester, 'transfer');
    expect(find.text('Categoria'), findsNothing, reason: 'transferência não tem categoria');
    await tester.enterText(find.byKey(const Key('field-amount')), '20000');
    await tester.enterText(find.byKey(const Key('field-description')), 'Guardar');
    await tapSave(tester);
    expect(find.text('Escolha a conta de destino.'), findsOneWidget);
    expect(transactions.createCalls, 0);
  });

  testWidgets('parcelamento mostra o valor das parcelas', (tester) async {
    await pumpForm(tester, 'expense');
    await tester.enterText(find.byKey(const Key('field-amount')), '240000');
    await tester.enterText(find.byKey(const Key('field-description')), 'Televisão');
    final parcelada = find.text('Parcelada');
    await tester.ensureVisible(parcelada);
    await tester.tap(parcelada);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('field-installments')), '12');
    await tester.pump();
    expect(find.textContaining('12x de R\$ 200,00'), findsOneWidget);
    await tapSave(tester);
    await tester.pumpAndSettle();
    expect(transactions.createdByKey.values.single.installments, 12);
  });

  testWidgets('recorrência é enviada', (tester) async {
    await pumpForm(tester, 'expense');
    await tester.enterText(find.byKey(const Key('field-amount')), '150000');
    await tester.enterText(find.byKey(const Key('field-description')), 'Aluguel');
    final recorrente = find.text('Recorrente');
    await tester.ensureVisible(recorrente);
    await tester.tap(recorrente);
    await tester.pump();
    await tapSave(tester);
    await tester.pumpAndSettle();
    final saved = transactions.createdByKey.values.single;
    expect(saved.recurrence, isNotNull);
    expect(saved.toPayload()['recurring'], {'frequency': 'monthly', 'interval_count': 1});
  });
}
