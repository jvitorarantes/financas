import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/env.dart';

class AppUpdate {
  const AppUpdate({required this.currentVersion, required this.latestVersion, required this.downloadUrl});
  final int currentVersion;
  final int latestVersion;
  final String downloadUrl;

  bool get hasUpdate => latestVersion > currentVersion;
}

/// Consulta a última versão do APK publicada em Releases do GitHub.
/// Cada APK tem o número de versão da tag (ex.: android-9 → versão 9).
abstract interface class UpdateRepository {
  Future<int> currentVersion();
  Future<AppUpdate> check();
}

/// "android-12" → 12
int? versionFromTag(String? tag) {
  final m = RegExp(r'(\d+)$').firstMatch(tag ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

class GithubUpdateRepository implements UpdateRepository {
  GithubUpdateRepository({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  @override
  Future<int> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  @override
  Future<AppUpdate> check() async {
    final current = await currentVersion();
    final res = await _http
        .get(
          Uri.parse('https://api.github.com/repos/${Env.releasesRepo}/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('release_check_failed');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final latest = versionFromTag(body['tag_name'] as String?) ?? 0;
    final assets = (body['assets'] as List?) ?? const [];
    final apk = assets.cast<Map<String, dynamic>>().where((a) => (a['name'] as String? ?? '').endsWith('.apk'));
    final url = apk.isEmpty
        ? 'https://github.com/${Env.releasesRepo}/releases/latest'
        : apk.first['browser_download_url'] as String;
    return AppUpdate(currentVersion: current, latestVersion: latest, downloadUrl: url);
  }
}

/// Só faz sentido no app Android instalado por APK (o site se atualiza sozinho).
bool get canSelfUpdate => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final updateRepositoryProvider = Provider<UpdateRepository>((ref) => GithubUpdateRepository());
