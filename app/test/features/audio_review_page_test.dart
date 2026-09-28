import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/data/repositories/ai_repository.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/features/audio/audio_flow_controller.dart';
import 'package:meu_financeiro/features/audio/audio_recorder.dart';
import 'package:meu_financeiro/features/audio/audio_review_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  late FakeTransactionsRepository transactions;
  late FakeAiRepository ai;

  setUp(() {
    transactions = FakeTransactionsRepository();
    ai = FakeAiRepository();
  });

  /// Grava, envia e abre a tela de conferência.
  Future<void> pumpReview(WidgetTester tester) async {
    await pumpRoutes(
      tester,
      initial: '/',
      overrides: [
        transactionsRepositoryProvider.overrideWithValue(transactions),
        aiRepositoryProvider.overrideWithValue(ai),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        audioRecorderServiceProvider.overrideWithValue(FakeRecorder()),
      ],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  final flow = ref.read(audioFlowProvider.notifier);
                  await flow.startRecording();
                  await Future<void>.delayed(const Duration(seconds: 3));
                  await flow.stopRecording();
                  await flow.submit();
                  if (context.mounted) context.push('/audio/review');
                },
                child: const Text('gravar'),
              ),
            ),
          ),
        ),
        GoRoute(path: '/audio/review', builder: (_, _) => const AudioReviewPage()),
      ],
    );
    await tester.tap(find.text('gravar'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('mostra transcrição e dados encontrados', (tester) async {
    await pumpReview(tester);
    expect(find.text('Confira sua movimentação'), findsOneWidget);
    expect(find.text('"Gastei 85 reais de gasolina hoje no cartão."'), findsOneWidget);
    expect(find.text('Despesa'), findsOneWidget);
    expect(find.text('R\$ 85,00'), findsOneWidget);
    expect(find.text('Gasolina'), findsOneWidget);
    expect(find.text('Transporte'), findsOneWidget);
    expect(find.text('Cartão de crédito'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Confirmar lançamento'), findsOneWidget);
    expect(transactions.createCalls, 0, reason: 'nada salvo sem confirmação');
  });

  testWidgets('"Confirmar lançamento" salva uma vez e volta ao início', (tester) async {
    await pumpReview(tester);
    final confirm = find.byKey(const Key('review-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(transactions.createCalls, 1);
    expect(transactions.createdByKey.values.single.amountCents, 8500);
    expect(find.text('gravar'), findsOneWidget);
  });

  testWidgets('"Cancelar" não salva', (tester) async {
    await pumpReview(tester);
    final cancel = find.byKey(const Key('review-cancel'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(transactions.createCalls, 0);
    expect(ai.calls.last, startsWith('cancel:'));
    expect(find.text('gravar'), findsOneWidget);
  });

  testWidgets('"Editar" permite corrigir os campos', (tester) async {
    await pumpReview(tester);
    final edit = find.byKey(const Key('review-edit'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-description')), 'Etanol');
    await tester.enterText(find.byKey(const Key('field-amount')), '9000');
    final confirm = find.byKey(const Key('review-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final saved = transactions.createdByKey.values.single;
    expect(saved.description, 'Etanol');
    expect(saved.amountCents, 9000);
  });

  testWidgets('ambiguidade: mostra a pergunta e exige o valor', (tester) async {
    ai.transcription = 'Gastei dinheiro no mercado.';
    ai.extraction = {
      ...ai.extraction,
      'amount': null,
      'amount_cents': null,
      'description': 'Mercado',
      'category': 'Alimentação',
      'payment_method': null,
      'requires_clarification': true,
      'missing_fields': ['amount'],
      'questions': ['Qual foi o valor?'],
    };
    await pumpReview(tester);
    expect(find.text('Qual foi o valor?'), findsOneWidget);
    final confirm = find.byKey(const Key('review-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(transactions.createCalls, 0);
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget, reason: 'abre a edição com o erro');
  });
}
