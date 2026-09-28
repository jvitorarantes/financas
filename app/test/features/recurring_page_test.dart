import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/finance_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/summaries.dart';
import 'package:meu_financeiro/features/recurring/recurring_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  late FakeFinanceRepository finance;

  setUp(() {
    final today = Dates.today();
    finance = FakeFinanceRepository()
      ..recurringList = [
        RecurringTransaction(
          id: 'r1',
          type: TransactionType.expense,
          amountCents: 150000,
          description: 'Aluguel',
          frequency: RecurrenceFrequency.monthly,
          intervalCount: 1,
          startDate: DateTime(today.year, today.month, 10),
          categoryName: 'Moradia',
          categoryId: 'cat-contas',
          accountId: 'acc-cc',
          accountName: 'Conta corrente',
        ),
        RecurringTransaction(
          id: 'r2',
          type: TransactionType.income,
          amountCents: 500000,
          description: 'Salário',
          frequency: RecurrenceFrequency.monthly,
          intervalCount: 1,
          startDate: DateTime(today.year, today.month, 5),
          categoryId: 'cat-sal',
          accountId: 'acc-cc',
        ),
      ];
  });

  Future<void> pumpPage(WidgetTester tester) => pumpRoutes(
    tester,
    initial: '/recurring',
    size: const Size(420, 1000),
    overrides: [
      financeRepositoryProvider.overrideWithValue(finance),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      transactionsRepositoryProvider.overrideWithValue(FakeTransactionsRepository()),
    ],
    routes: [GoRoute(path: '/recurring', builder: (_, _) => const RecurringPage())],
  );

  Future<void> openMenu(WidgetTester tester, String id, String action) async {
    await tester.tap(find.byKey(ValueKey('recurring-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }

  testWidgets('lista as recorrências com totais fixos do mês', (tester) async {
    await pumpPage(tester);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Salário'), findsOneWidget);
    expect(find.text('-R\$ 1.500,00'), findsWidgets);
    expect(find.text('R\$ 5.000,00'), findsOneWidget, reason: 'receitas fixas por mês');
    expect(find.textContaining('Todo mês · Próximo:'), findsNWidgets(2));
  });

  testWidgets('edita valor e periodicidade', (tester) async {
    await pumpPage(tester);
    await openMenu(tester, 'r1', 'Editar');
    await tester.enterText(find.byKey(const Key('recurring-edit-amount')), '160000');
    await tester.tap(find.byKey(const Key('recurring-edit-every')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A cada 3 meses').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recurring-edit-save')));
    await tester.pumpAndSettle();
    expect(finance.recurringCalls.single, contains('update:r1:'));
    expect(finance.recurringCalls.single, contains('amount_cents=160000'));
    expect(finance.recurringCalls.single, contains('interval_count=3'));
  });

  testWidgets('exclui após confirmar', (tester) async {
    await pumpPage(tester);
    await openMenu(tester, 'r1', 'Excluir');
    expect(find.textContaining('O que já foi pago continua no histórico'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(finance.recurringCalls, ['delete:r1']);
    expect(find.text('Aluguel'), findsNothing);
  });

  testWidgets('pausa após confirmar', (tester) async {
    await pumpPage(tester);
    await openMenu(tester, 'r2', 'Pausar');
    await tester.tap(find.widgetWithText(FilledButton, 'Pausar'));
    await tester.pumpAndSettle();
    expect(finance.recurringCalls, ['active:r2:false']);
  });

  test('próxima ocorrência respeita intervalo e data final', () {
    final r = RecurringTransaction(
      id: 'x',
      type: TransactionType.expense,
      amountCents: 1,
      description: 'Seguro',
      frequency: RecurrenceFrequency.monthly,
      intervalCount: 3,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 12, 31),
    );
    expect(r.nextOccurrence(DateTime(2026, 9, 28)), DateTime(2026, 10, 15));
    expect(r.nextOccurrence(DateTime(2026, 10, 16)), isNull);
  });
}
