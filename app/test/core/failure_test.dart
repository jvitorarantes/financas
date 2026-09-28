import 'package:flutter_test/flutter_test.dart';
import 'package:meu_financeiro/core/failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('erros de autenticação viram mensagens amigáveis', () {
    expect(
      toFailure(const AuthException('Invalid login credentials', code: 'invalid_credentials')).message,
      'E-mail ou senha incorretos.',
    );
    expect(
      toFailure(const AuthException('Signups not allowed for this instance', code: 'signup_disabled')).message,
      'O cadastro está fechado. Peça um acesso a quem administra o app.',
    );
    expect(
      toFailure(const AuthException('User already registered', code: 'user_already_exists')).message,
      'Já existe uma conta com esse e-mail.',
    );
  });

  test('erro desconhecido nunca expõe detalhes técnicos', () {
    final f = toFailure(Exception('NullPointer at line 42'));
    expect(f.message, 'Algo deu errado. Tente novamente.');
  });

  test('erros de rede e do banco', () {
    expect(
      toFailure(Exception('ClientException: Failed host lookup')).message,
      'Verifique sua conexão com a internet.',
    );
    expect(toFailure(const PostgrestException(message: 'invalid_amount')).message, 'Informe um valor maior que zero.');
  });
}
