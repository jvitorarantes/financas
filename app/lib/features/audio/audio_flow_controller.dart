import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/repositories/ai_repository.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/models/extraction.dart';
import '../../domain/models/transaction_draft.dart';
import 'audio_recorder.dart';

/// Estados do registro por áudio (mesmos nomes da tabela audio_sessions,
/// mais `idle` e `recorded`, que só existem no aparelho).
enum AudioFlowStatus {
  idle,
  recording,
  recorded,
  uploading,
  transcribing,
  extracting,
  needsReview,
  saving,
  completed,
  failed,
  cancelled;

  bool get isProcessing => this == uploading || this == transcribing || this == extracting;

  String get message => switch (this) {
    idle => 'Toque no microfone para gravar.',
    recording => 'Gravando… fale naturalmente.',
    recorded => 'Ouça o áudio ou envie para registrar.',
    uploading => 'Enviando áudio…',
    transcribing => 'Transcrevendo sua fala…',
    extracting => 'Entendendo a movimentação…',
    needsReview => 'Confira sua movimentação',
    saving => 'Salvando…',
    completed => 'Movimentação salva!',
    failed => 'Não deu certo.',
    cancelled => 'Gravação cancelada.',
  };
}

class AudioFlowState {
  const AudioFlowState({
    this.status = AudioFlowStatus.idle,
    this.sessionId,
    this.elapsed = Duration.zero,
    this.audio,
    this.transcription,
    this.extraction,
    this.draft,
    this.error,
    this.savedTransactionId,
  });

  final AudioFlowStatus status;
  final String? sessionId;
  final Duration elapsed;
  final RecordedAudio? audio;
  final String? transcription;
  final TransactionExtraction? extraction;
  final TransactionDraft? draft;
  final String? error;
  final String? savedTransactionId;

  AudioFlowState copyWith({
    AudioFlowStatus? status,
    String? sessionId,
    Duration? elapsed,
    RecordedAudio? audio,
    String? transcription,
    TransactionExtraction? extraction,
    TransactionDraft? draft,
    String? error,
    String? savedTransactionId,
    bool clearError = false,
    bool clearAudio = false,
  }) => AudioFlowState(
    status: status ?? this.status,
    sessionId: sessionId ?? this.sessionId,
    elapsed: elapsed ?? this.elapsed,
    audio: clearAudio ? null : audio ?? this.audio,
    transcription: transcription ?? this.transcription,
    extraction: extraction ?? this.extraction,
    draft: draft ?? this.draft,
    error: clearError ? null : error ?? this.error,
    savedTransactionId: savedTransactionId ?? this.savedTransactionId,
  );
}

class AudioFlowController extends Notifier<AudioFlowState> {
  static const maxDuration = Duration(seconds: 60);
  static const minDuration = Duration(milliseconds: 700);
  static const tick = Duration(milliseconds: 100);

  Timer? _ticker;

  AudioRecorderService get _recorder => ref.read(audioRecorderServiceProvider);
  AiRepository get _ai => ref.read(aiRepositoryProvider);
  TransactionsRepository get _transactions => ref.read(transactionsRepositoryProvider);

  @override
  AudioFlowState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const AudioFlowState();
  }

  /// 1–3: pede permissão e começa a gravar.
  Future<void> startRecording() async {
    if (state.status == AudioFlowStatus.recording ||
        state.status.isProcessing ||
        state.status == AudioFlowStatus.saving) {
      return;
    }
    await _discardAudio();
    state = AudioFlowState(sessionId: const Uuid().v4());
    final allowed = await _recorder.requestPermission().catchError((_) => false);
    if (!allowed) {
      state = state.copyWith(status: AudioFlowStatus.failed, error: AppFailure.microphoneDenied.message);
      return;
    }
    try {
      await _recorder.start();
    } catch (_) {
      state = state.copyWith(status: AudioFlowStatus.failed, error: 'Não foi possível iniciar a gravação.');
      return;
    }
    state = state.copyWith(status: AudioFlowStatus.recording, elapsed: Duration.zero);
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) {
      if (state.status != AudioFlowStatus.recording) return;
      final next = state.elapsed + tick;
      state = state.copyWith(elapsed: next);
      if (next >= maxDuration) stopRecording(); // limite de 60 s
    });
  }

  /// Para a gravação e deixa o usuário ouvir antes de enviar.
  Future<void> stopRecording() async {
    if (state.status != AudioFlowStatus.recording) return;
    _ticker?.cancel();
    final duration = state.elapsed > maxDuration ? maxDuration : state.elapsed;
    RecordedAudio? audio;
    try {
      audio = await _recorder.stop(duration);
    } catch (_) {
      audio = null;
    }
    if (audio == null || duration < minDuration) {
      if (audio != null) await _recorder.discard(audio);
      state = state.copyWith(
        status: AudioFlowStatus.failed,
        error: 'Gravação muito curta. Toque no microfone e fale sua movimentação.',
        clearAudio: true,
      );
      return;
    }
    state = state.copyWith(status: AudioFlowStatus.recorded, audio: audio, elapsed: duration);
  }

  /// Cancela em qualquer ponto antes de salvar. Nada é lançado.
  Future<void> cancel() async {
    _ticker?.cancel();
    final previous = state.status;
    if (previous == AudioFlowStatus.saving || previous == AudioFlowStatus.completed) return;
    if (previous == AudioFlowStatus.recording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    final sent = previous.index >= AudioFlowStatus.uploading.index || state.transcription != null;
    if (sent && state.sessionId != null) await _ai.cancelSession(state.sessionId!);
    await _discardAudio();
    state = state.copyWith(status: AudioFlowStatus.cancelled, clearAudio: true, clearError: true);
  }

  /// 7–11: envia, transcreve e interpreta. Não salva nada.
  Future<void> submit() async {
    final audio = state.audio;
    final sessionId = state.sessionId;
    if (audio == null || sessionId == null) return;
    if (state.status.isProcessing || state.status == AudioFlowStatus.saving) return;
    try {
      var transcription = state.transcription;
      if (transcription == null) {
        state = state.copyWith(status: AudioFlowStatus.uploading, clearError: true);
        transcription = await _ai.transcribe(
          sessionId: sessionId,
          bytes: audio.bytes,
          fileName: audio.fileName,
          mimeType: audio.mimeType,
          durationMs: audio.duration.inMilliseconds,
          onUploaded: () {
            if (state.status == AudioFlowStatus.uploading) {
              state = state.copyWith(status: AudioFlowStatus.transcribing);
            }
          },
        );
        if (state.status == AudioFlowStatus.cancelled) return;
      }
      state = state.copyWith(status: AudioFlowStatus.extracting, transcription: transcription, clearError: true);
      final response = await _ai.extract(sessionId);
      if (state.status == AudioFlowStatus.cancelled) return;
      final accounts = await ref.read(accountsProvider.future);
      final categories = await ref.read(categoriesProvider.future);
      final draft = response.extraction.toDraft(
        sessionId: sessionId,
        transcription: response.transcription.isEmpty ? transcription : response.transcription,
        categories: categories,
        accounts: accounts,
      );
      state = state.copyWith(
        status: AudioFlowStatus.needsReview,
        extraction: response.extraction,
        draft: draft,
        clearError: true,
      );
    } catch (e) {
      if (state.status == AudioFlowStatus.cancelled) return;
      state = state.copyWith(status: AudioFlowStatus.failed, error: toFailure(e).message);
    }
  }

  /// 12: o usuário corrige qualquer campo.
  void updateDraft(TransactionDraft draft) {
    if (state.status != AudioFlowStatus.needsReview) return;
    state = state.copyWith(draft: draft);
  }

  /// 13–15: salva uma única vez (chave de idempotência = id da sessão).
  /// Retorna os erros de validação (vazio = salvo ou já salvando).
  Future<Map<String, String>> confirm() async {
    final draft = state.draft;
    if (draft == null) return const {'draft': 'Nada para salvar.'};
    if (state.status == AudioFlowStatus.saving || state.status == AudioFlowStatus.completed) return const {};
    if (state.status != AudioFlowStatus.needsReview) return const {'draft': 'Nada para salvar.'};
    final errors = draft.validate();
    if (errors.isNotEmpty) return errors;

    state = state.copyWith(status: AudioFlowStatus.saving, clearError: true);
    try {
      final result = await _transactions.create(draft);
      state = state.copyWith(status: AudioFlowStatus.completed, savedTransactionId: result.transactionId);
      ref.read(financeRevisionProvider.notifier).bump();
      await _discardAudio();
      return const {};
    } catch (e) {
      state = state.copyWith(
        status: AudioFlowStatus.needsReview,
        error: toFailure(e, fallback: AppFailure.saveFailed).message,
      );
      return const {};
    }
  }

  Future<void> reset() async {
    _ticker?.cancel();
    if (state.status == AudioFlowStatus.recording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    await _discardAudio();
    state = const AudioFlowState();
  }

  Future<void> _discardAudio() async {
    final audio = state.audio;
    if (audio != null) {
      try {
        await _recorder.discard(audio);
      } catch (_) {}
    }
  }
}

final audioFlowProvider = NotifierProvider<AudioFlowController, AudioFlowState>(AudioFlowController.new);
