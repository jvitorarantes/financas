import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../supabase_providers.dart';

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    this.fullName,
    this.isAdmin = false,
    this.createdAt,
    this.lastSignInAt,
  });

  final String id;
  final String email;
  final String? fullName;
  final bool isAdmin;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  factory ManagedUser.fromJson(Map<String, dynamic> j) => ManagedUser(
    id: j['id'] as String,
    email: j['email'] as String? ?? '',
    fullName: j['full_name'] as String?,
    isAdmin: j['is_admin'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
    lastSignInAt: DateTime.tryParse(j['last_sign_in_at'] as String? ?? '')?.toLocal(),
  );
}

class ManagedUsers {
  const ManagedUsers({required this.users, required this.maxUsers});
  final List<ManagedUser> users;
  final int maxUsers;
}

/// Administração de contas (Edge Function admin-users; só o admin consegue).
abstract interface class AdminRepository {
  Future<ManagedUsers> list();
  Future<void> create({required String name, required String email, required String password});
  Future<void> setPassword(String userId, String password);
  Future<void> delete(String userId);
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._db);
  final SupabaseClient _db;

  Future<dynamic> _call(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke('admin-users', body: body).timeout(const Duration(seconds: 30));
      return res.data;
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<ManagedUsers> list() async {
    final data = (await _call({'action': 'list'}) as Map).cast<String, dynamic>();
    return ManagedUsers(
      users: ((data['users'] as List?) ?? const [])
          .map((e) => ManagedUser.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      maxUsers: (data['max_users'] as num?)?.toInt() ?? 20,
    );
  }

  @override
  Future<void> create({required String name, required String email, required String password}) =>
      _call({'action': 'create', 'full_name': name.trim(), 'email': email.trim(), 'password': password});

  @override
  Future<void> setPassword(String userId, String password) =>
      _call({'action': 'set_password', 'user_id': userId, 'password': password});

  @override
  Future<void> delete(String userId) => _call({'action': 'delete', 'user_id': userId});
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => SupabaseAdminRepository(ref.watch(supabaseProvider)),
);
