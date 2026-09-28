import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import 'audio_flow_controller.dart';

/// Abre a gravação já começando a gravar (toque no microfone = gravar).
Future<void> showAudioRecorderSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(audioFlowProvider.notifier).reset();
  if (!context.mounted) return;
  final goToReview = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => const AudioRecordSheet(autoStart: true),
  );
  final status = container.read(audioFlowProvider).status;
  if (goToReview == true && status == AudioFlowStatus.needsReview) {
    rootNavigatorKey.currentContext?.push('/audio/review');
  } else if (status != AudioFlowStatus.needsReview) {
    // Fechou a folha no meio: cancela (nada é salvo sem confirmação).
    await container.read(audioFlowProvider.notifier).cancel();
  }
}

class AudioRecordSheet extends ConsumerStatefulWidget {
  const AudioRecordSheet({super.key, this.autoStart = false});
  final bool autoStart;

  @override
  ConsumerState<AudioRecordSheet> createState() => _AudioRecordSheetState();
}

class _AudioRecordSheetState extends ConsumerState<AudioRecordSheet> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      Future.microtask(() => ref.read(audioFlowProvider.notifier).startRecording());
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String path) async {
    final player = _player ??= AudioPlayer()
      ..onPlayerComplete.listen((_) => mounted ? setState(() => _playing = false) : null);
    if (_playing) {
      await player.stop();
      setState(() => _playing = false);
      return;
    }
    try {
      await player.play(kIsWeb ? UrlSource(path) : DeviceFileSource(path));
      setState(() => _playing = true);
    } catch (_) {
      setState(() => _playing = false);
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioFlowProvider);
    final flow = ref.read(audioFlowProvider.notifier);
    ref.listen(audioFlowProvider.select((s) => s.status), (prev, next) {
      if (next == AudioFlowStatus.needsReview && prev != AudioFlowStatus.needsReview) {
        _player?.stop();
        Navigator.of(context).pop(true);
      }
    });

    final theme = Theme.of(context);
    final colors = context.financeColors;
    final s = state.status;

    Widget body;
    switch (s) {
      case AudioFlowStatus.idle:
      case AudioFlowStatus.cancelled:
        body = _column([
          _bigMic(context, onTap: flow.startRecording),
          const SizedBox(height: 16),
          Text('Toque para gravar', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Examples(),
        ]);
      case AudioFlowStatus.recording:
        final progress = state.elapsed.inMilliseconds / AudioFlowController.maxDuration.inMilliseconds;
        body = _column([
          _PulsingDot(color: colors.expense),
          const SizedBox(height: 12),
          Text(
            _fmt(state.elapsed),
            key: const Key('recording-timer'),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text('de 1:00', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: 12),
          Text(s.message),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('recording-cancel'),
                onPressed: flow.cancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar'),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                key: const Key('recording-stop'),
                onPressed: flow.stopRecording,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Concluir'),
              ),
            ],
          ),
        ]);
      case AudioFlowStatus.recorded:
        final audio = state.audio!;
        body = _column([
          IconButton.filledTonal(
            key: const Key('recording-play'),
            iconSize: 40,
            tooltip: _playing ? 'Parar' : 'Ouvir gravação',
            onPressed: () => _togglePlay(audio.playbackPath),
            icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(height: 8),
          Text('Gravação de ${_fmt(audio.duration)}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(s.message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('recording-send'),
            onPressed: () {
              _player?.stop();
              flow.submit();
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Enviar'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(onPressed: flow.cancel, child: const Text('Cancelar')),
              ),
              Expanded(
                child: TextButton(onPressed: flow.startRecording, child: const Text('Gravar de novo')),
              ),
            ],
          ),
        ]);
      case AudioFlowStatus.uploading:
      case AudioFlowStatus.transcribing:
      case AudioFlowStatus.extracting:
        body = _column([
          const SizedBox(height: 8),
          const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 5)),
          const SizedBox(height: 20),
          Text(s.message, key: const Key('processing-message'), style: theme.textTheme.titleMedium),
          if (state.transcription != null) ...[
            const SizedBox(height: 12),
            Text('"${state.transcription}"', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          _Steps(current: s),
          const SizedBox(height: 16),
          TextButton(onPressed: flow.cancel, child: const Text('Cancelar')),
        ]);
      case AudioFlowStatus.failed:
        body = _column([
          Icon(Icons.error_outline_rounded, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            state.error ?? s.message,
            key: const Key('audio-error'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          if (state.audio != null)
            FilledButton.icon(
              onPressed: flow.submit,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: flow.startRecording,
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Gravar de novo'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              rootNavigatorKey.currentContext?.push('/transactions/new?type=expense');
            },
            child: const Text('Registrar manualmente'),
          ),
        ]);
      case AudioFlowStatus.needsReview:
      case AudioFlowStatus.saving:
      case AudioFlowStatus.completed:
        body = _column([const CircularProgressIndicator()]);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: AnimatedSize(duration: const Duration(milliseconds: 200), child: body),
      ),
    );
  }

  Widget _column(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final c in children) Center(child: c)],
  );

  Widget _bigMic(BuildContext context, {required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Gravar áudio',
      child: InkResponse(
        onTap: onTap,
        radius: 56,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          child: Icon(Icons.mic_rounded, size: 48, color: scheme.onPrimary),
        ),
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      children: [
        Text('"Gastei 45 reais no almoço hoje"', style: style),
        Text('"Recebi 3200 de salário"', style: style),
        Text('"Comprei uma TV de 2400 em 12 vezes"', style: style),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final AudioFlowStatus current;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (AudioFlowStatus.uploading, 'Envio'),
      (AudioFlowStatus.transcribing, 'Transcrição'),
      (AudioFlowStatus.extracting, 'Interpretação'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (status, label) in steps) ...[
          Icon(
            current.index > status.index ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: current.index >= status.index ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
