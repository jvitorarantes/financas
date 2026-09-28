import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../domain/models/account.dart';
import '../../domain/models/category.dart';
import '../../domain/models/enums.dart';
import '../supabase_providers.dart';

/// Contas, categorias e perfil.
abstract interface class CatalogRepository {
  Future<List<Account>> accounts();
  Future<List<Category>> categories();
  Future<void> saveAccount({
    String? id,
    required String name,
    required AccountType type,
    required int initialBalanceCents,
    required bool includeInBalance,
  });
  Future<void> archiveAccount(String id, {bool archived = true});
  Future<void> saveCategory({
    String? id,
    required String name,
    required CategoryKind kind,
    required String icon,
    required String color,
  });
  Future<void> archiveCategory(String id, {bool archived = true});
  Future<String?> profileName();
  Future<bool> isAdmin();
  Future<void> updateProfileName(String name);
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._db);
  final SupabaseClient _db;

  String get _uid => _db.auth.currentUser!.id;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw toFailure(e);
    }
  }

  @override
  Future<List<Account>> accounts() => _guard(() async {
    final rows = await _db.from('account_balances').select().order('name');
    return rows.map(Account.fromBalanceRow).toList();
  });

  @override
  Future<List<Category>> categories() => _guard(() async {
    final rows = await _db.from('categories').select().order('name');
    return rows.map(Category.fromJson).toList();
  });

  @override
  Future<void> saveAccount({
    String? id,
    required String name,
    required AccountType type,
    required int initialBalanceCents,
    required bool includeInBalance,
  }) => _guard(() async {
    final data = {
      'name': name.trim(),
      'type': type.value,
      'initial_balance_cents': initialBalanceCents,
      'include_in_balance': includeInBalance,
    };
    if (id == null) {
      await _db.from('accounts').insert({...data, 'user_id': _uid});
    } else {
      await _db.from('accounts').update(data).eq('id', id);
    }
  });

  @override
  Future<void> archiveAccount(String id, {bool archived = true}) =>
      _guard(() => _db.from('accounts').update({'archived': archived}).eq('id', id));

  @override
  Future<void> saveCategory({
    String? id,
    required String name,
    required CategoryKind kind,
    required String icon,
    required String color,
  }) => _guard(() async {
    final data = {'name': name.trim(), 'kind': kind.value, 'icon': icon, 'color': color};
    if (id == null) {
      await _db.from('categories').insert({...data, 'user_id': _uid});
    } else {
      await _db.from('categories').update(data).eq('id', id);
    }
  });

  @override
  Future<void> archiveCategory(String id, {bool archived = true}) =>
      _guard(() => _db.from('categories').update({'archived': archived}).eq('id', id));

  @override
  Future<String?> profileName() => _guard(() async {
    final row = await _db.from('users').select('full_name').maybeSingle();
    return row?['full_name'] as String?;
  });

  @override
  Future<bool> isAdmin() async {
    try {
      final row = await _db.from('users').select('is_admin').maybeSingle();
      return row?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> updateProfileName(String name) =>
      _guard(() => _db.from('users').update({'full_name': name.trim()}).eq('id', _uid));
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SupabaseCatalogRepository(ref.watch(supabaseProvider)),
);

final isAdminProvider = FutureProvider<bool>((ref) => ref.watch(catalogRepositoryProvider).isAdmin());
