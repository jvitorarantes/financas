import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/data/repositories/update_repository.dart';
import 'package:meu_financeiro/features/settings/update_tile.dart';

import '../helpers/pump.dart';

class FakeUpdateRepository implements UpdateRepository {
  FakeUpdateRepository({required this.current, required this.latest, this.fail = false});
  final int current;
  final int latest;
  final bool fail;

  @override
  Future<int> currentVersion() async => current;

  @override
  Future<AppUpdate> check() async {
    if (fail) throw Exception('offline');
    return AppUpdate(
      currentVersion: current,
      latestVersion: latest,
      downloadUrl: 'https://github.com/x/y/releases/download/android-$latest/sniper-financas.apk',
    );
  }
}

void main() {
  setUpAll(initLocale);

  Future<List<Uri>> pumpTile(WidgetTester tester, FakeUpdateRepository repo) async {
    final opened = <Uri>[];
    await pumpRoutes(
      tester,
      initial: '/',
      overrides: [updateRepositoryProvider.overrideWithValue(repo)],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: UpdateTile(
              openUrl: (u) async {
                opened.add(u);
                return true;
              },
            ),
          ),
        ),
      ],
    );
    return opened;
  }

  testWidgets('mostra a versão instalada', (tester) async {
    await pumpTile(tester, FakeUpdateRepository(current: 8, latest: 8));
    expect(find.text('Versão instalada: 8'), findsOneWidget);
  });

  testWidgets('versão nova: baixa o APK', (tester) async {
    final opened = await pumpTile(tester, FakeUpdateRepository(current: 8, latest: 10));
    await tester.tap(find.byKey(const Key('check-update')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Versão 10 disponível (você tem a 8)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), endsWith('android-10/sniper-financas.apk'));
  });

  testWidgets('já atualizado', (tester) async {
    final opened = await pumpTile(tester, FakeUpdateRepository(current: 10, latest: 10));
    await tester.tap(find.byKey(const Key('check-update')));
    await tester.pumpAndSettle();
    expect(find.text('Você já está na versão mais nova (10).'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('sem internet: mensagem amigável', (tester) async {
    await pumpTile(tester, FakeUpdateRepository(current: 8, latest: 9, fail: true));
    await tester.tap(find.byKey(const Key('check-update')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível verificar agora. Verifique sua internet.'), findsOneWidget);
  });

  test('versão a partir da tag', () {
    expect(versionFromTag('android-12'), 12);
    expect(versionFromTag('v1'), 1);
    expect(versionFromTag(null), isNull);
  });
}
