import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/finance_repository.dart';
import 'package:meu_financeiro/features/budget/budget_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

class _RecordingFinance extends FakeFinanceRepository {
  final saved = <String>[];
  @override
  Future<void> saveBudget({String? categoryId, required int amountCents}) async =>
      saved.add('${categoryId ?? 'geral'}:$amountCents');
}

void main() {
  setUpAll(initLocale);

  for (final size in [const Size(390, 844), const Size(1300, 800)]) {
    testWidgets('define um limite a partir da tela vazia (${size.width.toInt()}px)', (tester) async {
      final finance = _RecordingFinance();
      await pumpRoutes(
        tester,
        size: size,
        initial: '/budget',
        overrides: [
          financeRepositoryProvider.overrideWithValue(finance),
          catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        ],
        routes: [GoRoute(path: '/budget', builder: (_, _) => const BudgetPage())],
      );
      expect(find.byKey(const Key('budget-add')), findsOneWidget, reason: 'botão no topo');
      await tester.tap(find.byKey(const Key('budget-add-empty')));
      await tester.pumpAndSettle();
      expect(find.text('Novo limite mensal'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alimentação').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '100000');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(finance.saved, ['cat-alim:100000']);
    });
  }
}
