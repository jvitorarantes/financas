import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/transaction.dart';
import 'package:meu_financeiro/features/transactions/transactions_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  testWidgets('mês seguinte já mostra a recorrência prevista para o dia certo', (tester) async {
    final today = Dates.today();
    final nextMonth = DateTime(today.year, today.month + 1, 10);
    final transactions = FakeTransactionsRepository()
      ..listResult = [
        FinanceTransaction(
          id: 'r-1',
          type: TransactionType.expense,
          status: TransactionStatus.pending,
          amountCents: 150000,
          description: 'Aluguel',
          date: nextMonth,
          accountId: 'acc-cc',
          source: TransactionSource.recurring,
          recurringTransactionId: 'rec-1',
          categoryName: 'Moradia',
        ),
      ];
    await pumpRoutes(
      tester,
      initial: '/transactions',
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(transactions),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      ],
      routes: [GoRoute(path: '/transactions', builder: (_, _) => const TransactionsPage())],
    );
    expect(find.text('Aluguel'), findsNothing, reason: 'mês atual');

    await tester.tap(find.byKey(const Key('month-next')));
    await tester.pumpAndSettle();
    expect(find.text(Dates.monthLabel(nextMonth)), findsOneWidget);
    expect(find.text('Aluguel'), findsOneWidget);
    expect(find.text('Previsto · ${Dates.formatDayMonth(nextMonth)}'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.byKey(const Key('forecast-summary')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('forecast-summary')), matching: find.text('-R\$ 1.500,00')),
      findsOneWidget,
      reason: 'total previsto',
    );
    // A despesa prevista já entra no total de despesas e no resultado do mês.
    expect(find.text('-R\$ 1.500,00'), findsNWidgets(4));
  });

  testWidgets('meses distantes geram as recorrências antes de listar', (tester) async {
    final transactions = FakeTransactionsRepository();
    await pumpRoutes(
      tester,
      initial: '/transactions',
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(transactions),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      ],
      routes: [GoRoute(path: '/transactions', builder: (_, _) => const TransactionsPage())],
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('month-next')));
      await tester.pumpAndSettle();
    }
    final today = Dates.today();
    final target = Dates.lastOfMonth(DateTime(today.year, today.month + 4));
    expect(transactions.materializedUntil, contains(target));
    expect(transactions.listFilters.last.from, DateTime(today.year, today.month + 4));
  });
}
