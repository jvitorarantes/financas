import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:meu_financeiro/app/theme.dart';

Future<void> initLocale() async {
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
}

/// Monta o app de teste com um GoRouter mínimo e os overrides informados.
Future<GoRouter> pumpRoutes(
  WidgetTester tester, {
  required List<RouteBase> routes,
  required String initial,
  List overrides = const [],
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: routes);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [...overrides],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

GoRoute stub(String path, String label) => GoRoute(
  path: path,
  builder: (_, _) => Scaffold(body: Text(label)),
);
