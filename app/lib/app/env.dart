/// Configuração pública do app, passada no build:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
/// A chave "anon" é pública por definição (o RLS protege os dados).
/// Chaves de IA NUNCA ficam no app: só nas Edge Functions.
abstract final class Env {
  // Padrões do projeto em produção (dados públicos: o RLS protege os dados).
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://svygqsovhkffabgwrdds.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ul-JN9LHBX50qjcCF7CEJQ_db6ryALS',
  );
  static const authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'br.com.meufinanceiro://login-callback',
  );

  /// Repositório onde o APK é publicado (Releases).
  static const releasesRepo = String.fromEnvironment('RELEASES_REPO', defaultValue: 'jvitorarantes/financas');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
