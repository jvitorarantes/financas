import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/core/failure.dart';
import 'package:meu_financeiro/data/repositories/ai_repository.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/data/repositories/transactions_repository.dart';
import 'package:meu_financeiro/domain/models/enums.dart';
import 'package:meu_financeiro/features/audio/audio_flow_controller.dart';
import 'package:meu_financeiro/features/audio/audio_recorder.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeRecorder recorder;
  late FakeAiRepository ai;
  late FakeTransactionsRepository transactions;
  late ProviderContainer container;
  late List<AudioFlowStatus> history;

  AudioFlowController flow() => container.read(audioFlowProvider.notifier);
  AudioFlowState state() => container.read(audioFlowProvider);

  setUp(() {
    recorder = FakeRecorder();
    ai = FakeAiRepository();
    transactions = FakeTransactionsRepository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        audioRecorderServiceProvider.overrideWithValue(recorder),
        aiRepositoryProvider.overrideWithValue(ai),
        transactionsRepositoryProvider.overrideWithValue(transactions),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      ],
    );
    history = [];
    container.listen(audioFlowProvider.select((s) => s.status), (_, next) => history.add(next), fireImmediately: true);
  });

  tearDown(() => container.dispose());

  /// Grava [seconds] segundos usando tempo simulado.
  void recordFor(int seconds) {
    fakeAsync((async) {
      flow().startRecording();
      async.flushMicrotasks();
      async.elapse(Duration(seconds: seconds));
      flow().stopRecording();
      async.flushMicrotasks();
    });
  }

  test('fluxo completo: grava, envia, confere e salva uma vez', () async {
    recordFor(4);
    expect(state().status, AudioFlowStatus.recorded);
    expect(state().audio!.duration, const Duration(seconds: 4));
    expect(recorder.calls, ['permission', 'start', 'stop']);

    await flow().submit();
    expect(state().status, AudioFlowStatus.needsReview);
    expect(state().transcription, 'Gastei 85 reais de gasolina hoje no cartão.');
    final draft = state().draft!;
    expect(draft.amountCents, 8500);
    expect(draft.categoryId, 'cat-transp');
    expect(draft.paymentMethod, PaymentMethod.creditCard);
    expect(draft.source, TransactionSource.audio);
    expect(draft.idempotencyKey, state().sessionId, reason: 'a sessão é a chave de idempotência');

    // Nada foi salvo antes da confirmação.
    expect(transactions.createCalls, 0);

    final errors = await flow().confirm();
    expect(errors, isEmpty);
    expect(state().status, AudioFlowStatus.completed);
    expect(transactions.createdByKey.length, 1);

    expect(history, [
      AudioFlowStatus.idle,
      AudioFlowStatus.recording,
      AudioFlowStatus.recorded,
      AudioFlowStatus.uploading,
      AudioFlowStatus.transcribing,
      AudioFlowStatus.extracting,
      AudioFlowStatus.needsReview,
      AudioFlowStatus.saving,
      AudioFlowStatus.completed,
    ]);
  });

  test('duplo toque em "Confirmar lançamento" cria um único lançamento', () async {
    recordFor(3);
    await flow().submit();
    transactions.gate = Completer<void>();
    final first = flow().confirm();
    final second = flow().confirm(); // ainda salvando
    expect(state().status, AudioFlowStatus.saving);
    transactions.gate!.complete();
    await Future.wait([first, second]);
    expect(transactions.createCalls, 1);
    expect(await flow().confirm(), isEmpty, reason: 'depois de concluído, não salva de novo');
    expect(transactions.createCalls, 1);
    expect(transactions.createdByKey.length, 1);
  });

  test('usuário corrige a interpretação antes de salvar', () async {
    recordFor(3);
    await flow().submit();
    flow().updateDraft(state().draft!.copyWith(amountCents: 9000, description: 'Etanol'));
    await flow().confirm();
    final saved = transactions.createdByKey.values.single;
    expect(saved.amountCents, 9000);
    expect(saved.description, 'Etanol');
  });

  test('valor não identificado impede salvar até o usuário informar', () async {
    ai.transcription = 'Gastei dinheiro no mercado.';
    ai.extraction = {
      ...ai.extraction,
      'amount': null,
      'amount_cents': null,
      'description': 'Mercado',
      'category': 'Alimentação',
      'requires_clarification': true,
      'missing_fields': ['amount'],
      'questions': ['Qual foi o valor?'],
    };
    recordFor(3);
    await flow().submit();
    expect(state().extraction!.questions, ['Qual foi o valor?']);
    final errors = await flow().confirm();
    expect(errors.keys, contains('amount'));
    expect(transactions.createCalls, 0);
    expect(state().status, AudioFlowStatus.needsReview);

    flow().updateDraft(state().draft!.copyWith(amountCents: 11500));
    expect(await flow().confirm(), isEmpty);
    expect(transactions.createdByKey.values.single.amountCents, 11500);
  });

  test('parcelamento por áudio', () async {
    ai.transcription = 'Comprei uma televisão de 2400 reais em 12 vezes.';
    ai.extraction = {
      ...ai.extraction,
      'amount': 2400,
      'amount_cents': 240000,
      'description': 'Televisão',
      'category': 'Compras',
      'installments': 12,
      'installment_amount_cents': 20000,
    };
    recordFor(3);
    await flow().submit();
    expect(state().draft!.installmentAmounts, List.filled(12, 20000));
    await flow().confirm();
    expect(transactions.createdByKey.values.single.toPayload()['installments'], 12);
  });

  test('transferência por áudio', () async {
    ai.extraction = {
      ...ai.extraction,
      'type': 'transfer',
      'amount_cents': 20000,
      'description': 'Transferência entre contas',
      'category': null,
      'account': 'Conta corrente',
      'destination_account': 'Poupança',
      'payment_method': null,
    };
    recordFor(3);
    await flow().submit();
    await flow().confirm();
    final p = transactions.createdByKey.values.single.toPayload();
    expect(p['type'], 'transfer');
    expect(p['category_id'], isNull);
    expect(p['destination_account_id'], 'acc-poup');
  });

  test('para sozinho aos 60 segundos', () {
    fakeAsync((async) {
      flow().startRecording();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 59));
      expect(state().status, AudioFlowStatus.recording);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(state().status, AudioFlowStatus.recorded);
      expect(state().audio!.duration, AudioFlowController.maxDuration);
    });
  });

  test('mostra a duração durante a gravação', () {
    fakeAsync((async) {
      flow().startRecording();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2500));
      expect(state().elapsed, const Duration(milliseconds: 2500));
      flow().cancel();
      async.flushMicrotasks();
    });
  });

  test('permissão negada: não grava e explica', () async {
    recorder.permission = false;
    await flow().startRecording();
    expect(state().status, AudioFlowStatus.failed);
    expect(state().error, AppFailure.microphoneDenied.message);
    expect(recorder.calls, ['permission']);
  });

  test('gravação curta demais é descartada', () {
    fakeAsync((async) {
      flow().startRecording();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 300));
      flow().stopRecording();
      async.flushMicrotasks();
      expect(state().status, AudioFlowStatus.failed);
      expect(state().audio, isNull);
      expect(recorder.calls, contains('discard'));
    });
  });

  test('cancelar durante a gravação não envia nem salva', () {
    fakeAsync((async) {
      flow().startRecording();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      flow().cancel();
      async.flushMicrotasks();
      expect(state().status, AudioFlowStatus.cancelled);
      expect(recorder.calls, contains('cancel'));
      expect(ai.calls, isEmpty);
    });
    expect(transactions.createCalls, 0);
  });

  test('cancelar na conferência marca a sessão e não salva', () async {
    recordFor(3);
    await flow().submit();
    await flow().cancel();
    expect(state().status, AudioFlowStatus.cancelled);
    expect(ai.calls.last, startsWith('cancel:'));
    expect(transactions.createCalls, 0);
    expect(await flow().confirm(), isNotEmpty, reason: 'depois de cancelar não há o que salvar');
    expect(transactions.createCalls, 0);
  });

  test('falha na transcrição mostra mensagem amigável e permite tentar de novo', () async {
    recordFor(3);
    ai.transcribeError = AppFailure.audioNotUnderstood;
    await flow().submit();
    expect(state().status, AudioFlowStatus.failed);
    expect(state().error, 'Não conseguimos entender o áudio. Tente novamente.');
    expect(state().audio, isNotNull, reason: 'o áudio fica para nova tentativa');

    ai.transcribeError = null;
    await flow().submit();
    expect(state().status, AudioFlowStatus.needsReview);
  });

  test('falha na interpretação reaproveita a transcrição', () async {
    recordFor(3);
    ai.extractError = networkError;
    await flow().submit();
    expect(state().status, AudioFlowStatus.failed);
    expect(state().error, 'Verifique sua conexão com a internet.');
    ai.extractError = null;
    await flow().submit();
    expect(ai.calls.where((c) => c.startsWith('transcribe')).length, 1);
    expect(state().status, AudioFlowStatus.needsReview);
  });

  test('erro ao salvar volta para a conferência e a mesma chave evita duplicar', () async {
    recordFor(3);
    await flow().submit();
    transactions.createError = AppFailure.saveFailed;
    await flow().confirm();
    expect(state().status, AudioFlowStatus.needsReview);
    expect(state().error, AppFailure.saveFailed.message);
    transactions.createError = null;
    await flow().confirm();
    await flow().confirm();
    expect(state().status, AudioFlowStatus.completed);
    expect(transactions.createdByKey.length, 1);
  });

  test('cada gravação tem sessão própria', () async {
    recordFor(3);
    final first = state().sessionId;
    await flow().reset();
    recordFor(3);
    expect(state().sessionId, isNot(first));
  });
}
