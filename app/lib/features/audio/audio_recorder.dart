import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'read_bytes_io.dart' if (dart.library.js_interop) 'read_bytes_web.dart';

class RecordedAudio {
  const RecordedAudio({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.duration,
    required this.playbackPath,
  });
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final Duration duration;

  /// Caminho do arquivo (mobile) ou URL blob (web) para ouvir antes de enviar.
  final String playbackPath;
}

/// Abstração do microfone (permite testar o fluxo sem hardware).
abstract interface class AudioRecorderService {
  /// Pede permissão ao sistema (mostra o diálogo na primeira vez).
  Future<bool> requestPermission();
  Future<void> start();
  Future<RecordedAudio?> stop(Duration duration);
  Future<void> cancel();
  Future<void> discard(RecordedAudio audio);
  Future<void> dispose();
}

class RecordAudioRecorder implements AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _webm = false;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    String path = '';
    AudioEncoder encoder = AudioEncoder.aacLc;
    if (kIsWeb) {
      _webm = await _recorder.isEncoderSupported(AudioEncoder.opus);
      encoder = _webm ? AudioEncoder.opus : AudioEncoder.wav;
    } else {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/meu_financeiro_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
        noiseSuppress: true,
        echoCancel: true,
      ),
      path: path,
    );
  }

  @override
  Future<RecordedAudio?> stop(Duration duration) async {
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) return null;
    final bytes = await readRecordingBytes(path);
    if (bytes.isEmpty) return null;
    final (name, mime) = kIsWeb
        ? (_webm ? ('audio.webm', 'audio/webm') : ('audio.wav', 'audio/wav'))
        : ('audio.m4a', 'audio/mp4');
    return RecordedAudio(bytes: bytes, fileName: name, mimeType: mime, duration: duration, playbackPath: path);
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> discard(RecordedAudio audio) => deleteRecording(audio.playbackPath);

  @override
  Future<void> dispose() => _recorder.dispose();
}

final audioRecorderServiceProvider = Provider<AudioRecorderService>((ref) {
  final recorder = RecordAudioRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
