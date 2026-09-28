import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meu_financeiro/core/failure.dart';
import 'package:meu_financeiro/data/repositories/admin_repository.dart';
import 'package:meu_financeiro/data/repositories/auth_repository.dart';
import 'package:meu_financeiro/data/repositories/catalog_repository.dart';
import 'package:meu_financeiro/features/admin/admin_page.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

class FakeAdminRepository implements AdminRepository {
  final users = <ManagedUser>[
    const ManagedUser(id: 'u1', email: 'ana@teste.com', fullName: 'Ana', isAdmin: true),
    const ManagedUser(id: 'u2', email: 'joao@teste.com', fullName: 'João'),
  ];
  final calls = <String>[];
  Object? createError;

  @override
  Future<ManagedUsers> list() async => ManagedUsers(users: [...users], maxUsers: 20);

  @override
  Future<void> create({required String name, required String email, required String password}) async {
    calls.add('create:$name:$email:${password.length}');
    if (createError != null) throw createError!;
    users.add(ManagedUser(id: 'u${users.length + 1}', email: email, fullName: name));
  }

  @override
  Future<void> setPassword(String userId, String password) async => calls.add('password:$userId');

  @override
  Future<void> delete(String userId) async {
    calls.add('delete:$userId');
    users.removeWhere((u) => u.id == userId);
  }
}

void main() {
  setUpAll(initLocale);

  late FakeAdminRepository admin;
  late FakeCatalogRepository catalog;

  setUp(() {
    admin = FakeAdminRepository();
    catalog = FakeCatalogRepository()..admin = true;
  });

  Future<void> pumpAdmin(WidgetTester tester) => pumpRoutes(
    tester,
    initial: '/admin',
    size: const Size(900, 1000),
    overrides: [
      adminRepositoryProvider.overrideWithValue(admin),
      catalogRepositoryProvider.overrideWithValue(catalog),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()..signedIn = true),
    ],
    routes: [GoRoute(path: '/admin', builder: (_, _) => const AdminPage())],
  );

  testWidgets('lista as contas e o limite', (tester) async {
    await pumpAdmin(tester);
    expect(find.text('2 de 20 contas'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('João'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('cria usuário com e-mail e senha e mostra os dados para enviar', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('admin-new-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-user-name')), 'Maria');
    await tester.enterText(find.byKey(const Key('new-user-email')), 'maria@teste.com');
    await tester.enterText(find.byKey(const Key('new-user-password')), 'senha-da-maria');
    await tester.tap(find.byKey(const Key('new-user-save')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['create:Maria:maria@teste.com:14']);
    expect(find.textContaining('Senha: senha-da-maria'), findsOneWidget);
    await tester.tap(find.text('Pronto'));
    await tester.pumpAndSettle();
    expect(find.text('3 de 20 contas'), findsOneWidget);
  });

  testWidgets('valida os dados do novo usuário', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('admin-new-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-user-email')), 'maria@');
    await tester.enterText(find.byKey(const Key('new-user-password')), '123');
    await tester.tap(find.byKey(const Key('new-user-save')));
    await tester.pump();
    expect(find.text('Informe seu nome.'), findsOneWidget);
    expect(find.text('E-mail inválido.'), findsOneWidget);
    expect(find.text('A senha deve ter pelo menos 8 caracteres.'), findsOneWidget);
    expect(admin.calls, isEmpty);
  });

  testWidgets('mostra o erro do servidor (ex.: e-mail já usado)', (tester) async {
    admin.createError = const AppFailure('Já existe uma conta com esse e-mail.', code: 'admin_error');
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('admin-new-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-user-name')), 'João');
    await tester.enterText(find.byKey(const Key('new-user-email')), 'joao@teste.com');
    await tester.tap(find.byKey(const Key('new-user-save')));
    await tester.pumpAndSettle();
    expect(find.text('Já existe uma conta com esse e-mail.'), findsOneWidget);
  });

  testWidgets('exclui conta após confirmação', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byTooltip('Ações').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(admin.calls, ['delete:u2']);
    expect(find.text('João'), findsNothing);
  });

  testWidgets('quem não é admin não vê nada', (tester) async {
    catalog.admin = false;
    await pumpAdmin(tester);
    expect(find.text('Apenas o administrador pode acessar esta página.'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
  });

  test('senha gerada tem tamanho certo e sem caracteres confusos', () {
    final p = generatePassword();
    expect(p.length, 10);
    expect(RegExp(r'[0O1lI]').hasMatch(p), isFalse);
  });
}
