import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Erro exibível ao usuário. Nunca carrega stack trace nem detalhe técnico.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});
  final String message;
  final String? code;

  static const connection = AppFailure('Verifique sua conexão com a internet.', code: 'network');
  static const generic = AppFailure('Algo deu errado. Tente novamente.', code: 'internal');
  static const saveFailed = AppFailure('Não conseguimos salvar a movimentação. Tente novamente.', code: 'save_failed');
  static const audioNotUnderstood = AppFailure(
    'Não conseguimos entender o áudio. Tente novamente.',
    code: 'transcription_failed',
  );
  static const amountNotFound = AppFailure('Não foi possível identificar o valor.', code: 'amount');
  static const microphoneDenied = AppFailure(
    'Precisamos de acesso ao microfone para gravar. Libere nas configurações do aparelho.',
    code: 'microphone_denied',
  );

  @override
  String toString() => message;
}

/// Mensagens das Edge Functions (mesmos códigos de supabase/functions/_shared/http.ts).
const _functionMessages = <String, String>{
  'unauthorized': 'Sua sessão expirou. Entre novamente.',
  'audio_too_long': 'O áudio pode ter no máximo 60 segundos.',
  'audio_too_large': 'O áudio ficou grande demais. Tente uma gravação mais curta.',
  'unsupported_audio': 'Formato de áudio não suportado.',
  'transcription_failed': 'Não conseguimos entender o áudio. Tente novamente.',
  'empty_transcription': 'Não conseguimos entender o áudio. Tente novamente.',
  'extraction_failed': 'Não conseguimos interpretar a movimentação. Preencha os dados manualmente.',
  'rate_limited': 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.',
  'session_not_found': 'Gravação não encontrada. Grave novamente.',
};

/// Erros de validação do banco (create_transaction) → texto amigável.
const _databaseMessages = <String, String>{
  'invalid_amount': 'Informe um valor maior que zero.',
  'missing_description': 'Informe uma descrição.',
  'missing_account': 'Escolha uma conta.',
  'invalid_transfer_accounts': 'Escolha contas de origem e destino diferentes.',
  'transfer_cannot_repeat': 'Transferências não podem ser parceladas nem recorrentes.',
  'installments_only_for_expense': 'Só despesas podem ser parceladas.',
  'installments_and_recurring': 'Uma movimentação não pode ser parcelada e recorrente ao mesmo tempo.',
  'future_transaction_cannot_be_paid': 'Uma movimentação com data futura ainda não pode estar paga.',
  'invalid_installments': 'O número de parcelas deve ser entre 2 e 120.',
};

AppFailure toFailure(Object error, {AppFailure fallback = AppFailure.generic}) {
  if (error is AppFailure) return error;
  if (error is TimeoutException) return AppFailure.connection;
  final text = error.toString();
  if (error is AuthException) return _authFailure(error);
  if (error is PostgrestException) {
    for (final entry in _databaseMessages.entries) {
      if (error.message.contains(entry.key)) return AppFailure(entry.value, code: entry.key);
    }
    if (error.code == '23505') {
      return const AppFailure('Esse registro já existe.', code: 'duplicate');
    }
    if (error.code == '42501' || error.code == 'PGRST301') {
      return const AppFailure('Sua sessão expirou. Entre novamente.', code: 'unauthorized');
    }
    return fallback;
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is Map) {
      final code = (details['error'] as Map)['code']?.toString();
      // Mensagens da administração já vêm prontas para o usuário.
      if (code == 'admin_error') {
        return AppFailure((details['error'] as Map)['message']?.toString() ?? fallback.message, code: code);
      }
      final message = _functionMessages[code];
      if (message != null) return AppFailure(message, code: code);
    }
    return fallback;
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('XMLHttpRequest') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable')) {
    return AppFailure.connection;
  }
  return fallback;
}

AppFailure functionErrorFromBody(Object? body, {AppFailure fallback = AppFailure.generic}) {
  if (body is Map && body['error'] is Map) {
    final code = (body['error'] as Map)['code']?.toString();
    final message = _functionMessages[code];
    if (message != null) return AppFailure(message, code: code);
  }
  return fallback;
}

AppFailure _authFailure(AuthException e) {
  final m = e.message.toLowerCase();
  final code = e.code ?? '';
  if (code == 'invalid_credentials' || m.contains('invalid login')) {
    return const AppFailure('E-mail ou senha incorretos.', code: 'invalid_credentials');
  }
  if (code == 'email_not_confirmed' || m.contains('not confirmed')) {
    return const AppFailure(
      'Confirme seu e-mail antes de entrar. Verifique sua caixa de entrada.',
      code: 'email_not_confirmed',
    );
  }
  if (code == 'signup_disabled' || m.contains('signups not allowed')) {
    return const AppFailure(
      'O cadastro está fechado. Peça um acesso a quem administra o app.',
      code: 'signup_disabled',
    );
  }
  if (m.contains('database error saving new user')) {
    return const AppFailure('Não foi possível criar a conta. Fale com quem administra o app.', code: 'signup_rejected');
  }
  if (code == 'user_already_exists' || m.contains('already registered')) {
    return const AppFailure('Já existe uma conta com esse e-mail.', code: 'user_already_exists');
  }
  if (code == 'weak_password' || m.contains('password should')) {
    return const AppFailure('Escolha uma senha mais forte (mínimo de 8 caracteres).', code: 'weak_password');
  }
  if (code == 'over_email_send_rate_limit' || m.contains('rate limit')) {
    return const AppFailure('Muitas tentativas. Aguarde alguns minutos.', code: 'rate_limited');
  }
  if (code == 'same_password') {
    return const AppFailure('A nova senha deve ser diferente da anterior.', code: 'same_password');
  }
  return const AppFailure('Não foi possível concluir. Tente novamente.', code: 'auth');
}
