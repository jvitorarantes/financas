import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../domain/models/extraction.dart';
import '../../domain/models/summaries.dart';
import '../supabase_providers.dart';

class ExtractionResponse {
  const ExtractionResponse({required this.transcription, required this.extraction, this.usedAi = true});
  final String transcription;
  final TransactionExtraction extraction;
  final bool usedAi;
}

/// Áudio → texto → dados estruturados, e análises. Tudo passa pelas Edge
/// Functions: as chaves de IA ficam só no servidor.
abstract interface class AiRepository {
  /// [onUploaded] é chamado quando o envio termina e a transcrição começa.
  Future<String> transcribe({
    required String sessionId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
    void Function()? onUploaded,
  });
  Future<ExtractionResponse> extract(String sessionId);
  Future<ExtractionResponse> extractText(String text);
  Future<void> cancelSession(String sessionId);
  Future<List<Insight>> insights(DateTime month);
  Future<List<Insight>> savedInsights(DateTime month);
}

class SupabaseAiRepository implements AiRepository {
  SupabaseAiRepository(this._db, {http.Client? httpClient}) : _http = httpClient ?? http.Client();
  final SupabaseClient _db;
  final http.Client _http;

  @override
  Future<String> transcribe({
    required String sessionId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationMs,
    void Function()? onUploaded,
  }) async {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw const AppFailure('Sua sessão expirou. Entre novamente.', code: 'unauthorized');
    final multipart = http.MultipartRequest('POST', Uri.parse('${Env.supabaseUrl}/functions/v1/transcribe-audio'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['apikey'] = Env.supabaseAnonKey
      ..fields['session_id'] = sessionId
      ..fields['duration_ms'] = durationMs.toString()
      ..files.add(
        http.MultipartFile.fromBytes('audio', bytes, filename: fileName, contentType: MediaType.parse(mimeType)),
      );
    try {
      final streamed = await _http
          .send(_UploadProgressRequest(multipart, onUploaded ?? () {}))
          .timeout(const Duration(seconds: 75));
      final body = await streamed.stream.bytesToString();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      if (streamed.statusCode != 200) {
        throw functionErrorFromBody(decoded, fallback: AppFailure.audioNotUnderstood);
      }
      final text = (decoded as Map)['transcription'] as String?;
      if (text == null || text.trim().isEmpty) throw AppFailure.audioNotUnderstood;
      return text;
    } catch (e) {
      throw toFailure(e, fallback: AppFailure.audioNotUnderstood);
    }
  }

  ExtractionResponse _parseExtraction(dynamic data) {
    final map = (data as Map).cast<String, dynamic>();
    return ExtractionResponse(
      transcription: map['transcription'] as String? ?? '',
      extraction: TransactionExtraction.fromJson((map['extraction'] as Map).cast<String, dynamic>()),
      usedAi: map['used_ai'] as bool? ?? false,
    );
  }

  @override
  Future<ExtractionResponse> extract(String sessionId) async {
    try {
      final res = await _db.functions
          .invoke('extract-transaction', body: {'session_id': sessionId})
          .timeout(const Duration(seconds: 75));
      return _parseExtraction(res.data);
    } catch (e) {
      throw toFailure(
        e,
        fallback: const AppFailure(
          'Não conseguimos interpretar a movimentação. Preencha os dados manualmente.',
          code: 'extraction_failed',
        ),
      );
    }
  }

  @override
  Future<ExtractionResponse> extractText(String text) async {
    try {
      final res = await _db.functions
          .invoke('extract-transaction', body: {'text': text})
          .timeout(const Duration(seconds: 75));
      return _parseExtraction(res.data);
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<void> cancelSession(String sessionId) async {
    try {
      await _db.from('audio_sessions').update({'status': 'cancelled'}).eq('id', sessionId).neq('status', 'completed');
    } catch (_) {
      // Cancelar é melhor esforço: a sessão sem confirmação nunca vira lançamento.
    }
  }

  @override
  Future<List<Insight>> insights(DateTime month) async {
    try {
      final m = Dates.iso(Dates.firstOfMonth(month)).substring(0, 7);
      final res = await _db.functions
          .invoke('financial-insights', body: {'month': m})
          .timeout(const Duration(seconds: 90));
      final list = ((res.data as Map)['insights'] as List?) ?? const [];
      return list.map((e) => Insight.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<List<Insight>> savedInsights(DateTime month) async {
    try {
      final rows = await _db
          .from('ai_insights')
          .select()
          .eq('month', Dates.iso(Dates.firstOfMonth(month)))
          .order('created_at');
      return rows.map(Insight.fromJson).toList();
    } catch (e) {
      throw toFailure(e);
    }
  }
}

/// Envia o multipart avisando quando o último byte foi entregue.
class _UploadProgressRequest extends http.BaseRequest {
  _UploadProgressRequest(this._inner, this._onUploaded) : super(_inner.method, _inner.url);
  final http.MultipartRequest _inner;
  final void Function() _onUploaded;

  @override
  http.ByteStream finalize() {
    final stream = _inner.finalize();
    headers.addAll(_inner.headers);
    contentLength = _inner.contentLength;
    super.finalize();
    var notified = false;
    return http.ByteStream(
      stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleDone: (sink) {
            if (!notified) {
              notified = true;
              _onUploaded();
            }
            sink.close();
          },
        ),
      ),
    );
  }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => SupabaseAiRepository(ref.watch(supabaseProvider)));
