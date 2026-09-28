import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/core/dates.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/domain/models/transaction.dart';
import 'package:meu_financeiro/features/reminders/reminders_widgets.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  FinanceTransaction bill(String id, String description, int days) => FinanceTransaction(
    id: id,
    type: TransactionType.expense,
    status: TransactionStatus.pending,
    amountCents: 18000,
    description: description,
    date: Dates.today().add(Duration(days: days)),
    accountId: 'acc-cc',
  );

  testWidgets('avisos aparecem até marcar como paga', (tester) async {
    final transactions = FakeTransactionsRepository()
      ..pendingResult = [bill('luz', 'Energia', 3), bill('agua', 'Água', -2), bill('longe', 'IPVA', 20)];
    await pumpRoutes(
      tester,
      initial: '/',
      overrides: [transactionsRepositoryProvider.overrideWithValue(transactions)],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Column(children: [NotificationBell(), RemindersBanner()])),
        ),
      ],
    );
    expect(find.text('Energia'), findsOneWidget);
    expect(find.text('Água'), findsOneWidget);
    expect(find.text('IPVA'), findsNothing, reason: 'vence em mais de 7 dias');
    expect(find.textContaining('Vence em 3 dias'), findsOneWidget);
    expect(find.textContaining('Venceu há 2 dias'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'contador do sino');

    await tester.tap(find.byKey(const ValueKey('reminder-paid-luz')));
    await tester.pumpAndSettle();
    expect(transactions.paidIds, ['luz']);
    expect(find.text('Energia'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('o sino abre a lista completa', (tester) async {
    final transactions = FakeTransactionsRepository()..pendingResult = [bill('luz', 'Energia', 0)];
    await pumpRoutes(
      tester,
      initial: '/',
      overrides: [transactionsRepositoryProvider.overrideWithValue(transactions)],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Center(child: NotificationBell())),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('notification-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Notificações'), findsOneWidget);
    expect(find.textContaining('Vence hoje'), findsOneWidget);
  });
}
