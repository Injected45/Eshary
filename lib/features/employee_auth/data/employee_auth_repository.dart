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
    required this.permissions,
    required this.branchId,
  });

  final String sessionId;
  final String subUserId;
  final String parentAdminId;
  final String employeeName;

  /// Permission keys granted by the admin (employee_permissions.dart).
  /// Empty for a new employee: the app shows nothing until some are granted.
  final List<String> permissions;
  final String? branchId;

  factory EmployeeIdentity.fromRow(Map<String, dynamic> row) =>
      EmployeeIdentity(
        sessionId: row['session_id'] as String,
        subUserId: row['sub_user_id'] as String,
        parentAdminId: row['parent_admin_id'] as String,
        employeeName: row['employee_name'] as String,
        permissions: ((row['permissions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        branchId: row['branch_id'] as String?,
      );
}

/// Who a scanned QR belongs to, shown to the employee before confirming.
class QrPreview {
  const QrPreview({required this.employeeName, required this.phoneNumber});
  final String employeeName;
  final String phoneNumber;
}

/// What one employee did on one account (from employee_my_account()).
/// No balances: only counts and totals of their own operations.
class MyAccountRow {
  const MyAccountRow({
    required this.companyName,
    required this.exchangeName,
    required this.ourCode,
    required this.outOpenCount,
    required this.outOpenTotal,
    required this.outClosedCount,
    required this.outClosedTotal,
    required this.inOpenCount,
    required this.inOpenTotal,
    required this.inClosedCount,
    required this.inClosedTotal,
  });

  final String companyName;
  final String exchangeName;
  final String? ourCode;
  final int outOpenCount;
  final double outOpenTotal;
  final int outClosedCount;
  final double outClosedTotal;
  final int inOpenCount;
  final double inOpenTotal;
  final int inClosedCount;
  final double inClosedTotal;

  static double _d(Object? v) => double.tryParse('$v') ?? 0;
  static int _i(Object? v) => int.tryParse('$v') ?? 0;

  factory MyAccountRow.fromJson(Map<String, dynamic> j) => MyAccountRow(
        companyName: (j['company_name'] as String?) ?? '',
        exchangeName: (j['exchange_name'] as String?) ?? '',
        ourCode: j['our_code'] as String?,
        outOpenCount: _i(j['out_open_count']),
        outOpenTotal: _d(j['out_open_total']),
        outClosedCount: _i(j['out_closed_count']),
        outClosedTotal: _d(j['out_closed_total']),
        inOpenCount: _i(j['in_open_count']),
        inOpenTotal: _d(j['in_open_total']),
        inClosedCount: _i(j['in_closed_count']),
        inClosedTotal: _d(j['in_closed_total']),
      );
}

/// The server refused an OTP step. [code] is machine-readable (the same words
/// riendlyError maps to Arabic); [wait] is the seconds before a resend.
class OtpRefused implements Exception {
  const OtpRefused(this.code, {this.wait, this.left});
  final String code;
  final int? wait;
  final int? left;

  @override
  String toString() => code;
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
      // No rows = wrong phone or code (the database counts the failure).
      if (res.isEmpty) throw StateError('invalid_credentials');
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
            permissions: const <String>[],
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

  /// Makes sure there is an anonymous session to call the QR RPCs with.
  /// An existing anonymous session is reused so preview → login share one.
  Future<void> _ensureAnonymous() async {
    if (_client.auth.currentUser?.isAnonymous == true) return;
    await _client.auth.signInAnonymously();
  }

  /// Looks up who a scanned QR belongs to (name + phone) without consuming
  /// it. Throws `invalid_qr` for unknown, used or expired QRs.
  Future<QrPreview> previewQr(String token) async {
    await _ensureAnonymous();
    try {
      final res = await _client.rpc<List<dynamic>>(
        'employee_qr_preview',
        params: {'p_token': token},
      );
      if (res.isEmpty) {
        throw StateError('employee_qr_preview returned no rows');
      }
      final row = res.first as Map<String, dynamic>;
      return QrPreview(
        employeeName: row['employee_name'] as String,
        phoneNumber: row['phone_number'] as String,
      );
    } catch (e) {
      await cancelPending();
      rethrow;
    }
  }

  /// Signs in with a scanned QR token (single use, 10 minutes). Binds the
  /// device exactly like the phone + code login. [googleEmail] is attached
  /// to the employee record as an informational label for the admin.
  Future<EmployeeIdentity> signInWithQr({
    required String token,
    String? googleEmail,
  }) async {
    final deviceId = await _deviceIdService.get();
    await _ensureAnonymous();
    try {
      final res = await _client.rpc<List<dynamic>>(
        'employee_login_qr',
        params: {'p_token': token, 'p_device_id': deviceId},
      );
      if (res.isEmpty) throw StateError('employee_login_qr returned no rows');
      final row = res.first as Map<String, dynamic>;
      return await currentIdentity() ??
          EmployeeIdentity(
            sessionId: row['session_id'] as String,
            subUserId: row['sub_user_id'] as String,
            parentAdminId: row['parent_admin_id'] as String,
            employeeName: row['employee_name'] as String,
            permissions: const <String>[],
            branchId: null,
          );
    } catch (e) {
      await cancelPending();
      rethrow;
    }
  }

  /// Sends a 6-digit code by WhatsApp to the phone number the admin registered
  /// for the employee behind [token]. Returns the masked number it went to.
  /// Throws [OtpRefused] (wrong e-mail, too soon, too many sends, ...).
  Future<String> requestOtp(String token) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'employee_request_otp',
      params: {'p_token': token},
    );
    if (res['ok'] == true) return (res['phone'] as String?) ?? '';
    throw OtpRefused(
      (res['code'] as String?) ?? 'send_failed',
      wait: (res['wait'] as num?)?.toInt(),
    );
  }

  /// Checks the code the employee typed. Throws [OtpRefused] when it is wrong,
  /// expired, or the attempts ran out (which also burns the QR).
  Future<void> verifyOtp(String token, String otp) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'employee_verify_otp',
      params: {'p_token': token, 'p_otp': otp},
    );
    if (res['ok'] == true) return;
    throw OtpRefused(
      (res['code'] as String?) ?? 'invalid_otp',
      left: (res['left'] as num?)?.toInt(),
    );
  }

  /// Drops a lingering anonymous session that never became an employee
  /// session (failed or abandoned QR sign-in).
  Future<void> cancelPending() async {
    try {
      if (_client.auth.currentUser?.isAnonymous == true) {
        await _client.auth.signOut();
      }
    } catch (_) {}
  }

  /// The signed-in employee's own work per account (permission accounts_own).
  Future<List<MyAccountRow>> myAccount() async {
    final res = await _client.rpc<List<dynamic>>('employee_my_account');
    return res
        .cast<Map<String, dynamic>>()
        .map(MyAccountRow.fromJson)
        .toList();
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
