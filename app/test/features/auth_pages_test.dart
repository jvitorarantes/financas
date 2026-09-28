import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/core/failure.dart';
import 'package:meu_financeiro/data/repositories/auth_repository.dart';
import 'package:meu_financeiro/features/auth/login_page.dart';
import 'package:meu_financeiro/features/auth/password_pages.dart';
import 'package:meu_financeiro/features/auth/signup_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(initLocale);

  late FakeAuthRepository auth;
  setUp(() => auth = FakeAuthRepository());

  Future<void> pumpAuth(WidgetTester tester, String initial) => pumpRoutes(
    tester,
    initial: initial,
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
    ],
  );

  group('login', () {
    testWidgets('valida campos antes de enviar', (tester) async {
      await pumpAuth(tester, '/login');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Informe seu e-mail.'), findsOneWidget);
      expect(find.text('Informe sua senha.'), findsOneWidget);
      expect(auth.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('login-email')), 'ana@');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('E-mail inválido.'), findsOneWidget);
    });

    testWidgets('entra com e-mail e senha', (tester) async {
      await pumpAuth(tester, '/login');
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@teste.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'senha-forte-123');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn:ana@teste.com']);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('mostra erro amigável sem detalhes técnicos', (tester) async {
      auth.signInError = const AppFailure('E-mail ou senha incorretos.', code: 'invalid_credentials');
      await pumpAuth(tester, '/login');
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@teste.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'errada-123');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    });

    testWidgets('erro inesperado vira mensagem genérica', (tester) async {
      auth.signInError = Exception('stack trace secreto: at line 42');
      await pumpAuth(tester, '/login');
      await tester.enterText(find.byKey(const Key('login-email')), 'ana@teste.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'senha-123456');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('stack trace'), findsNothing);
      expect(find.text('Algo deu errado. Tente novamente.'), findsOneWidget);
    });
  });

  group('cadastro', () {
    testWidgets('senhas diferentes não são aceitas', (tester) async {
      await pumpAuth(tester, '/signup');
      await tester.enterText(find.byKey(const Key('signup-name')), 'Ana');
      await tester.enterText(find.byKey(const Key('signup-email')), 'ana@teste.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'senha-forte-1');
      await tester.enterText(find.byType(TextFormField).at(3), 'senha-forte-2');
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();
      expect(find.text('As senhas não conferem.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('senha curta é recusada', (tester) async {
      await pumpAuth(tester, '/signup');
      await tester.enterText(find.byType(TextFormField).at(2), '123');
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();
      expect(find.text('A senha deve ter pelo menos 8 caracteres.'), findsOneWidget);
    });

    testWidgets('cria a conta e pede confirmação do e-mail', (tester) async {
      await pumpAuth(tester, '/signup');
      await tester.enterText(find.byKey(const Key('signup-name')), 'Ana Souza');
      await tester.enterText(find.byKey(const Key('signup-email')), 'ana@teste.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'senha-forte-1');
      await tester.enterText(find.byType(TextFormField).at(3), 'senha-forte-1');
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signUp:Ana Souza:ana@teste.com']);
      expect(find.text('Confirme seu e-mail'), findsOneWidget);
    });
  });

  testWidgets('recuperação de senha envia o link', (tester) async {
    await pumpAuth(tester, '/forgot-password');
    await tester.enterText(find.byType(TextFormField), 'ana@teste.com');
    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset:ana@teste.com']);
    expect(find.text('Verifique seu e-mail'), findsOneWidget);
  });
}
