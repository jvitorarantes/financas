import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readRecordingBytes(String path) => File(path).readAsBytes();

Future<void> deleteRecording(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
