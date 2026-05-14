import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/sub_user.dart';

/// Pair returned by [SubUsersRepository.create]: the new row id plus the
/// plain (un-hashed) login code that must be shown to the admin exactly
/// once. The server never persists the plain code.
class SubUserCreateResult {
  const SubUserCreateResult({required this.id, required this.plainCode});
  final String id;
  final String plainCode;
}

class SubUsersRepository {
  SubUsersRepository(this._client);
  final SupabaseClient _client;

  Future<List<SubUser>> list() async {
    final rows = await _client
        .from('sub_users')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => SubUser.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<SubUserCreateResult> create({
    required String employeeName,
    required String phoneNumber,
    required SubUserRole role,
    String? branchId,
  }) async {
    final res = await _client.rpc<List<dynamic>>(
      'create_sub_user',
      params: {
        'p_employee_name': employeeName,
        'p_phone_number': phoneNumber,
        'p_role': subUserRoleToDb(role),
        'p_branch_id': branchId,
      },
    );
    final rows = res;
    if (rows.isEmpty) {
      throw StateError('create_sub_user returned no rows');
    }
    final row = rows.first as Map<String, dynamic>;
    return SubUserCreateResult(
      id: row['id'] as String,
      plainCode: row['plain_code'] as String,
    );
  }

  /// Regenerates the login code, resets `login_code_used`, and unbinds the
  /// device so the employee can authenticate fresh on a new phone.
  Future<String> regenerateCode(String id) async {
    final res = await _client.rpc<String>(
      'regenerate_sub_user_code',
      params: {'p_id': id},
    );
    return res;
  }

  /// Unbinds the employee from their current device without rotating the
  /// login code. Closes any active session so the current device loses
  /// access immediately. Used when the employee got a new phone but still
  /// remembers their original code.
  Future<void> resetDevice(String id) async {
    await _client.rpc<void>(
      'reset_sub_user_device',
      params: {'p_id': id},
    );
  }

  Future<void> updateStatus({
    required String id,
    required SubUserStatus status,
  }) async {
    await _client.from('sub_users').update({
      'status': subUserStatusToDb(status),
      'disabled_at': status == SubUserStatus.disabled
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('sub_users').delete().eq('id', id);
  }
}

final subUsersRepositoryProvider = Provider<SubUsersRepository>((ref) {
  return SubUsersRepository(ref.watch(supabaseClientProvider));
});
