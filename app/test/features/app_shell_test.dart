import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/finance_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/summaries.dart';
import 'package:meu_financeiro/features/dashboard/dashboard_page.dart';
import 'package:meu_financeiro/features/shell/app_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  Future<void> pumpShell(WidgetTester tester, Size size, {FakeFinanceRepository? finance}) => pumpRoutes(
    tester,
    size: size,
    initial: '/',
    overrides: [
      transactionsRepositoryProvider.overrideWithValue(FakeTransactionsRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      financeRepositoryProvider.overrideWithValue(finance ?? FakeFinanceRepository()),
    ],
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          stub('/transactions', 'lista'),
          stub('/budget', 'orçamento'),
        ],
      ),
      stub('/transactions/new', 'nova'),
    ],
  );

  testWidgets('celular: navegação inferior e botão "+" com gravação em destaque', (tester) async {
    await pumpShell(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byKey(const Key('fab-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-audio')), findsOneWidget);
    expect(find.text('Adicionar receita'), findsOneWidget);
    expect(find.text('Adicionar despesa'), findsOneWidget);
    expect(find.text('Transferir'), findsOneWidget);
    await tester.tap(find.text('Adicionar despesa'));
    await tester.pumpAndSettle();
    expect(find.text('nova'), findsOneWidget);
  });

  testWidgets('desktop: menu lateral com todas as seções', (tester) async {
    await pumpShell(tester, const Size(1400, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in [
      'Dashboard',
      'Movimentações',
      'Orçamento',
      'Planejamento',
      'Análises',
      'Metas',
      'Configurações',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byKey(const Key('sidebar-record')), findsOneWidget);
  });

  testWidgets('dashboard mostra saldo atual, projetado e totais do mês', (tester) async {
    final finance = FakeFinanceRepository()
      ..summaryValue = DashboardSummary(
        month: DateTime(2026, 9),
        currentBalanceCents: 315410,
        monthIncomeCents: 320000,
        monthExpenseCents: 4590,
        pendingExpenseCents: 80000,
        pendingIncomeCents: 100000,
        projectedBalanceCents: 235410,
      );
    await pumpShell(tester, const Size(1400, 1200), finance: finance);
    expect(find.text('R\$ 3.154,10'), findsWidgets);
    expect(find.text('R\$ 2.354,10'), findsWidgets);
    expect(find.text('R\$ 3.200,00'), findsOneWidget);
    expect(find.text('R\$ 45,90'), findsOneWidget);
    expect(find.text('Você possui R\$ 800,00 em contas futuras.'), findsOneWidget);
    expect(find.text('Não inclui R\$ 1.000,00 a receber.'), findsOneWidget);
  });
}
