import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import 'device_id_service.dart';

/// Identity of the currently signed-in employee, returned by
/// `current_employee_session()` and by a successful `employee_login` call.
class EmployeeIdentity {
  const EmployeeIdentity({
    required this.sessionId,
    required this.subUserId,
    required this.parentAdminId,
    required this.employeeName,
    required this.role,
    required this.branchId,
  });

  final String sessionId;
  final String subUserId;
  final String parentAdminId;
  final String employeeName;

  /// Raw enum value from sub_users.role: 'entry' | 'exit' | 'both'.
  final String role;
  final String? branchId;

  factory EmployeeIdentity.fromRow(Map<String, dynamic> row) =>
      EmployeeIdentity(
        sessionId: row['session_id'] as String,
        subUserId: row['sub_user_id'] as String,
        parentAdminId: row['parent_admin_id'] as String,
        employeeName: row['employee_name'] as String,
        role: row['role'] as String,
        branchId: row['branch_id'] as String?,
      );
}

class EmployeeAuthRepository {
  EmployeeAuthRepository(this._client, this._deviceIdService);

  final SupabaseClient _client;
  final DeviceIdService _deviceIdService;

  /// Signs in anonymously (creates a fresh `auth.users` row with
  /// `is_anonymous = true`) and then runs `employee_login` to verify the
  /// phone+code and bind the session to this device.
  ///
  /// Throws on bad credentials, disabled accounts, or device mismatch —
  /// callers should display [friendlyError] of the thrown exception.
  Future<EmployeeIdentity> signIn({
    required String phone,
    required String code,
  }) async {
    final deviceId = await _deviceIdService.get();

    // If a previous anonymous session is lingering, drop it first so the
    // resulting JWT belongs to a fresh anonymous user (avoids reusing a
    // session that was already closed server-side).
    if (_client.auth.currentUser?.isAnonymous == true) {
      await _client.auth.signOut();
    }

    await _client.auth.signInAnonymously();

    try {
      final res = await _client.rpc<List<dynamic>>(
        'employee_login',
        params: {
          'p_phone': phone,
          'p_code': code,
          'p_device_id': deviceId,
        },
      );
      if (res.isEmpty) {
        throw StateError('employee_login returned no rows');
      }
      final row = res.first as Map<String, dynamic>;
      // current_employee_session has extra columns (role, branch_id) that
      // employee_login does not return — fetch the full identity now so
      // the rest of the app reads from one consistent source.
      return await currentIdentity() ??
          EmployeeIdentity(
            sessionId: row['session_id'] as String,
            subUserId: row['sub_user_id'] as String,
            parentAdminId: row['parent_admin_id'] as String,
            employeeName: row['employee_name'] as String,
            role: 'both',
            branchId: null,
          );
    } catch (e) {
      // Failed login → drop the anonymous session so we don't leave the
      // user in a half-signed-in state on the auth screen.
      try {
        await _client.auth.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  /// Returns the active session's identity, or null if no active session.
  Future<EmployeeIdentity?> currentIdentity() async {
    if (_client.auth.currentUser?.isAnonymous != true) return null;
    final res = await _client.rpc<List<dynamic>>('current_employee_session');
    if (res.isEmpty) return null;
    return EmployeeIdentity.fromRow(res.first as Map<String, dynamic>);
  }

  /// Closes the server-side session row and signs the anonymous user out.
  Future<void> signOut() async {
    try {
      await _client.rpc<void>('employee_logout');
    } catch (_) {
      // Even if the RPC fails (network etc.), drop the local session so
      // the UI returns to /sign-in.
    }
    await _client.auth.signOut();
  }
}

final employeeAuthRepositoryProvider = Provider<EmployeeAuthRepository>((ref) {
  return EmployeeAuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(deviceIdServiceProvider),
  );
});
