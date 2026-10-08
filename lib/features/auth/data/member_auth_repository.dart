import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../license/data/license_repository.dart';

/// The server refused a step of the e-mail + phone + WhatsApp-code sign-in.
/// [code] is machine-readable (the words `friendlyError` maps to Arabic).
class MemberRefused implements Exception {
  const MemberRefused(this.code, {this.wait, this.left});

  final String code;

  /// Seconds before another code may be requested (`too_soon`).
  final int? wait;

  /// Wrong-code attempts remaining (`invalid_otp`).
  final int? left;

  @override
  String toString() => code;
}

/// Result of a successful code request.
class MemberOtpSent {
  const MemberOtpSent({
    required this.phoneMasked,
    required this.isNew,
    required this.needsEmail,
  });
  final String phoneMasked;
  final bool isNew;

  /// First time for this account: the e-mail must be proven too, with the
  /// code Supabase mailed to it. Later sign-ins need the WhatsApp code only.
  final bool needsEmail;
}

/// Password-less sign-in / sign-up for subscribers: e-mail + phone + a code
/// sent by WhatsApp to that phone. The code is checked only by the
/// `member-session` Edge Function, which also issues the session.
class MemberAuthRepository {
  MemberAuthRepository(this._client, this._licenseRepo);

  final SupabaseClient _client;
  final LicenseRepository _licenseRepo;

  Future<MemberOtpSent> requestOtp(String email, String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_request_otp',
      params: {'p_email': email.trim(), 'p_phone': phone.trim()},
    );
    if (res['ok'] == true) {
      final needsEmail = res['needsEmail'] == true;
      if (needsEmail) {
        // First time: mail the e-mail code (Supabase Auth). Only done after the
        // database accepted the e-mail + phone pair, so it cannot be abused to
        // mail arbitrary addresses.
        try {
          await _client.auth.signInWithOtp(
            email: email.trim(),
            shouldCreateUser: true,
          );
        } on AuthException {
          throw const MemberRefused('email_send_failed');
        }
      }
      return MemberOtpSent(
        phoneMasked: (res['phone'] as String?) ?? '',
        isNew: res['isNew'] == true,
        needsEmail: needsEmail,
      );
    }
    throw MemberRefused(
      (res['code'] as String?) ?? 'send_failed',
      wait: (res['wait'] as num?)?.toInt(),
    );
  }

  /// Verifies the code and signs in. On success the auth state changes and
  /// the router moves the user by itself (pending activation for new
  /// accounts, home for approved ones).
  Future<void> verify(
    String email,
    String phone,
    String otp, {
    String? emailCode,
  }) async {
    final Map<String, dynamic> data;
    try {
      final res = await _client.functions.invoke(
        'member-session',
        body: {
          'email': email.trim(),
          'phone': phone.trim(),
          'otp': otp.trim(),
          if (emailCode != null) 'emailCode': emailCode.trim(),
        },
      );
      data = (res.data as Map).cast<String, dynamic>();
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['code'] as String? : null;
      throw MemberRefused(code ?? 'server_error');
    }

    if (data['ok'] != true) {
      throw MemberRefused(
        (data['code'] as String?) ?? 'invalid_otp',
        left: (data['left'] as num?)?.toInt(),
      );
    }

    // Drop any cached licence from a previous user before the new session.
    await _licenseRepo.clearCache();
    await _client.auth.verifyOTP(
      tokenHash: data['tokenHash'] as String,
      type: OtpType.email,
    );
  }
}

final memberAuthRepositoryProvider = Provider<MemberAuthRepository>((ref) {
  return MemberAuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(licenseRepositoryProvider),
  );
});
