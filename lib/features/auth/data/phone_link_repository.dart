import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import 'member_auth_repository.dart' show MemberRefused;

/// Links the phone of a NEW account (0050_google_signup_phone_link.sql). The
/// person is already signed in with Google, which proved the e-mail; the only
/// thing left to prove is the phone, with one WhatsApp code. The e-mail is
/// taken from the session by the database, never sent from here.
class PhoneLinkRepository {
  PhoneLinkRepository(this._client);
  final SupabaseClient _client;

  /// Does this account still have to link a phone?
  Future<bool> needsPhone() async {
    final res = await _client.rpc<dynamic>('member_needs_phone');
    return res == true;
  }

  /// Sends the 4-digit WhatsApp code. Returns the masked phone.
  Future<String> requestCode(String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_request_phone_otp',
      params: {'p_phone': phone.trim()},
    );
    if (res['ok'] == true) return (res['phone'] as String?) ?? '';
    throw MemberRefused(
      (res['code'] as String?) ?? 'send_failed',
      wait: (res['wait'] as num?)?.toInt(),
    );
  }

  /// Checks the code and links the phone.
  Future<void> confirm(String phone, String otp) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'member_confirm_phone',
      params: {'p_phone': phone.trim(), 'p_otp': otp.trim()},
    );
    if (res['ok'] == true) return;
    throw MemberRefused(
      (res['code'] as String?) ?? 'invalid_otp',
      left: (res['left'] as num?)?.toInt(),
    );
  }
}

final phoneLinkRepositoryProvider = Provider<PhoneLinkRepository>((ref) {
  return PhoneLinkRepository(ref.watch(supabaseClientProvider));
});

/// Whether the signed-in account must still link a phone. Re-read when the
/// user changes; the link screen invalidates it after a successful link.
final needsPhoneProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  return ref.watch(phoneLinkRepositoryProvider).needsPhone();
});
