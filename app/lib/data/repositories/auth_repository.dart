import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env.dart';
import '../../core/failure.dart';
import '../supabase_providers.dart';

abstract interface class AuthRepository {
  Stream<AuthChangeEvent> get events;
  bool get isSignedIn;
  String? get email;
  Future<void> signIn({required String email, required String password});

  /// Retorna true quando é preciso confirmar o e-mail antes de entrar.
  Future<bool> signUp({required String name, required String email, required String password});

  /// true enquanto não existe nenhuma conta (primeiro acesso = administrador).
  Future<bool> needsSetup();
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<AuthChangeEvent> get events => _client.auth.onAuthStateChange.map((s) => s.event);

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<bool> signUp({required String name, required String email, required String password}) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name.trim()},
        emailRedirectTo: Env.authRedirectUrl,
      );
      return res.session == null;
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<bool> needsSetup() async {
    try {
      return await _client.rpc('needs_setup') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authRedirectUrl);
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw toFailure(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => SupabaseAuthRepository(ref.watch(supabaseProvider)));

final needsSetupProvider = FutureProvider<bool>((ref) => ref.watch(authRepositoryProvider).needsSetup());
