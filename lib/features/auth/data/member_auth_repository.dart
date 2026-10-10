import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../license/data/license_repository.dart';

/// The name the Edge Function (supabase/functions/member-session/index.ts) is
/// deployed under on the Supabase project. The dashboard editor named the
/// deployment "super-handler" and the name cannot be changed there, so the app
/// calls it by that name. Change this one line if it is ever redeployed as
/// "member-session" (or any other name).
const kMemberSessionFunction = 'super-handler';

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

/// Who an invitation is for.
class InvitePreview {
  const InvitePreview({required this.name, required this.phoneMasked});
  final String name;
  final String phoneMasked;
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

/// Password-less sign-in for subscribers by e-mail + phone, by phone alone, or
/// with an invitation QR, always confirmed by a code sent by WhatsApp to the
/// phone. The code is checked only by the
/// member-session Edge Function (deployed under the name in
/// [kMemberSessionFunction]), which also issues the session.
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
  }) =>
      _exchange({
        'email': email.trim(),
        'phone': phone.trim(),
        'otp': otp.trim(),
        if (emailCode != null) 'emailCode': emailCode.trim(),
      });

  // ---- sign-in by phone number (a member whose phone is linked) -----------

  /// Sends the WhatsApp code to a linked phone. Returns the masked phone.
  Future<String> phoneLoginRequest(String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_phone_login_request',
      params: {'p_phone': phone.trim()},
    );
    return _sentOrThrow(res);
  }

  Future<void> phoneLogin(String phone, String otp) => _exchange({
        'action': 'phone',
        'phone': phone.trim(),
        'otp': otp.trim(),
      });

  // ---- invitation (QR from the administrator) ------------------------------

  /// Who the invitation is for (name + masked phone), or throws
  /// [MemberRefused] ('invite_invalid') when it is used, expired or revoked.
  Future<InvitePreview> invitePreview(String token) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_invite_preview',
      params: {'p_token': token},
    );
    if (res['ok'] != true) {
      throw MemberRefused((res['code'] as String?) ?? 'invite_invalid');
    }
    return InvitePreview(
      name: (res['name'] as String?) ?? '',
      phoneMasked: (res['phone'] as String?) ?? '',
    );
  }

  /// Sends the WhatsApp code to the phone the administrator registered; the
  /// typed [phone] must be that phone (5 wrong ones burn the invitation).
  Future<String> inviteRequestOtp(String token, String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_invite_request_otp',
      params: {'p_token': token, 'p_phone': phone.trim()},
    );
    return _sentOrThrow(res);
  }

  /// Checks the code, creates the account with the licence the administrator
  /// chose, and signs in.
  Future<void> redeemInvite(String token, String phone, String otp) =>
      _exchange({
        'action': 'invite',
        'token': token,
        'phone': phone.trim(),
        'otp': otp.trim(),
      });

  // ---- shared ---------------------------------------------------------------

  String _sentOrThrow(Map<String, dynamic> res) {
    if (res['ok'] == true) return (res['phone'] as String?) ?? '';
    throw MemberRefused(
      (res['code'] as String?) ?? 'send_failed',
      wait: (res['wait'] as num?)?.toInt(),
      left: (res['left'] as num?)?.toInt(),
    );
  }

  /// Sends the proofs to the Edge Function and signs in with the one-time
  /// token it returns.
  Future<void> _exchange(Map<String, dynamic> body) async {
    final Map<String, dynamic> data;
    try {
      final res = await _client.functions.invoke(
        kMemberSessionFunction,
        body: body,
      );
      data = (res.data as Map).cast<String, dynamic>();
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['code'] as String? : null;
      final detail = details is Map ? details['detail'] as String? : null;
      throw MemberRefused(
        detail == null ? (code ?? 'server_error') : '${code ?? 'server_error'}: $detail',
      );
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
