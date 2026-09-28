import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// No navegador o gravador devolve uma URL "blob:"; lemos os bytes dela.
Future<Uint8List> readRecordingBytes(String path) async => (await http.get(Uri.parse(path))).bodyBytes;

Future<void> deleteRecording(String path) async {}
