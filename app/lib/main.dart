import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');

  if (!Env.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  // A sessão fica salva no aparelho (sessão persistente) e é renovada sozinha.
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  runApp(
    ProviderScope(
      // Erros de rede são tratados na tela (botão "Tentar novamente").
      retry: (retryCount, error) => null,
      child: const MeuFinanceiroApp(),
    ),
  );
}
