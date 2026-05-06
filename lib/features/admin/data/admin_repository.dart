import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/admin_user_row.dart';
export '../domain/admin_user_row.dart';

class AdminRepository {
  AdminRepository(this._client);
  final SupabaseClient _client;

  Future<List<AdminUserRow>> listUsers() async {
    final res = await _client.rpc<List<dynamic>>('admin_list_users');
    return res
        .cast<Map<String, dynamic>>()
        .map(AdminUserRow.fromJson)
        .toList();
  }

  Future<void> activateTrial(String email) async {
    await _client.rpc<dynamic>(
      'admin_activate_trial',
      params: {'p_user_email': email},
    );
  }

  Future<void> activateLifetime(String email) async {
    await _client.rpc<dynamic>(
      'admin_activate_lifetime',
      params: {'p_user_email': email},
    );
  }

  Future<void> block(String email) async {
    await _client.rpc<dynamic>(
      'admin_block',
      params: {'p_user_email': email},
    );
  }

  Future<void> setPending(String email) async {
    await _client.rpc<dynamic>(
      'admin_set_pending',
      params: {'p_user_email': email},
    );
  }

  Future<void> grantAdmin(String email) async {
    await _client.rpc<dynamic>(
      'admin_grant_admin',
      params: {'p_user_email': email},
    );
  }

  Future<void> revokeAdmin(String email) async {
    await _client.rpc<dynamic>(
      'admin_revoke_admin',
      params: {'p_user_email': email},
    );
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

/// Cached snapshot of the admin user list. Invalidate after every admin
/// action so the screen reflects the new state without manual reloads.
final adminUsersListProvider =
    FutureProvider.autoDispose<List<AdminUserRow>>((ref) async {
  return ref.watch(adminRepositoryProvider).listUsers();
});
