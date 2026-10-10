import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../../license/data/license_repository.dart';
import '../domain/trial_models.dart';

/// The name the Edge Function (supabase/functions/member-session/index.ts) is
/// deployed under on the Supabase project. The dashboard editor named the
/// deployment "super-handler" and the name cannot be changed there, so the app
/// calls it by that name. Change this one line if it is ever redeployed as
/// "member-session" (or any other name).
const kMemberSessionFunction = 'super-handler';

const _followKey = 'trial:follow-token';

/// The follow token kept on this device, or null (read without a server).
String? savedFollowToken(JsonCache cache) {
  final t = cache.readString(_followKey);
  return (t == null || t.isEmpty) ? null : t;
}

/// A running clock for countdowns: elapsed time since the app started, which
/// the phone's wall-clock settings cannot move.
final Stopwatch kMonotonic = Stopwatch()..start();

/// The applicant's side: asking for a trial, following the request, proving
/// the phone with the WhatsApp code, signing in again. Every time and every
/// decision comes from the database; the app only shows it.
class TrialRepository {
  TrialRepository(this._client, this._cache, this._licenseRepo);

  final SupabaseClient _client;
  final JsonCache _cache;
  final LicenseRepository _licenseRepo;

  // ---- the follow token (kept on this device only) --------------------------

  String? get savedToken => savedFollowToken(_cache);

  Future<void> forgetToken() => _cache.writeString(_followKey, '');

  // ---- the request ----------------------------------------------------------

  Future<void> submit({
    required String manager,
    required String business,
    required String phone,
    required bool consent,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'trial_submit',
      params: {
        'p_manager': manager,
        'p_business': business,
        'p_phone': phone,
        'p_consent': consent,
      },
    );
    _throwIfRefused(res);
    await _cache.writeString(_followKey, res['followToken'] as String);
  }

  Future<TrialFollow> follow(String token) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'trial_follow',
      params: {'p_token': token},
    );
    _throwIfRefused(res);
    return TrialFollow.fromJson(res);
  }

  Future<void> updatePhone(String token, String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'trial_update_phone',
      params: {'p_token': token, 'p_phone': phone},
    );
    _throwIfRefused(res);
  }

  /// Asks for a (new) WhatsApp code. Returns the seconds to wait before the
  /// next one.
  Future<int> requestCode(String token) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'trial_request_code',
      params: {'p_token': token},
    );
    _throwIfRefused(res);
    return (res['wait'] as num?)?.toInt() ?? 60;
  }

  /// Enters the code. The trial STARTS here, on the server, and the session
  /// that follows moves the router.
  Future<void> activate(String token, String code) =>
      _exchange({'action': 'activate', 'followToken': token, 'code': code});

  // ---- sign-in of an existing subscriber ------------------------------------

  Future<int> loginRequest(String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'login_request',
      params: {'p_phone': phone},
    );
    _throwIfRefused(res);
    return (res['wait'] as num?)?.toInt() ?? 60;
  }

  Future<void> loginVerify(String phone, String code) =>
      _exchange({'action': 'login', 'phone': phone, 'code': code});

  // ---- the subscriber's own state ---------------------------------------------

  Future<SubscriptionState> subscriptionState() async {
    final res = await _client.rpc<Map<String, dynamic>>('subscription_state');
    return SubscriptionState.fromJson(res, kMonotonic.elapsedMilliseconds);
  }

  Future<void> subscriptionRequest(String kind, {String? note}) async {
    await _client.rpc<dynamic>(
      'subscription_request',
      params: {'p_kind': kind, 'p_note': note},
    );
  }

  // ---- changing the number of an existing account -------------------------

  Future<Map<String, dynamic>> phoneChangeStatus() =>
      _client.rpc<Map<String, dynamic>>('phone_change_status');

  /// Sends a code to the NEW number; returns the seconds before a resend.
  Future<int> phoneChangeStart(String phone) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'phone_change_start',
      params: {'p_new': phone},
    );
    _throwIfRefused(res);
    return (res['wait'] as num?)?.toInt() ?? 60;
  }

  Future<int> phoneChangeResend() async {
    final res =
        await _client.rpc<Map<String, dynamic>>('phone_change_resend');
    _throwIfRefused(res);
    return (res['wait'] as num?)?.toInt() ?? 60;
  }

  Future<void> phoneChangeVerify(String code) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'phone_change_verify',
      params: {'p_code': code},
    );
    _throwIfRefused(res);
  }

  Future<void> phoneChangeCancel() async {
    await _client.rpc<dynamic>('phone_change_cancel');
  }

  // ---- shared -----------------------------------------------------------------

  void _throwIfRefused(Map<String, dynamic> res) {
    if (res['ok'] == true) return;
    throw TrialRefused(
      (res['code'] as String?) ?? 'server_error',
      wait: (res['wait'] as num?)?.toInt(),
      left: (res['left'] as num?)?.toInt(),
    );
  }

  /// Sends the proof to the Edge Function and signs in with the one-time token
  /// it returns.
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
      throw TrialRefused(
        detail == null
            ? (code ?? 'server_error')
            : '${code ?? 'server_error'}: $detail',
      );
    }
    _throwIfRefused(data);

    // Drop any cached licence from a previous user before the new session.
    await _licenseRepo.clearCache();
    await _client.auth.verifyOTP(
      tokenHash: data['tokenHash'] as String,
      type: OtpType.email,
    );
    await forgetToken();
  }
}

final trialRepositoryProvider = Provider<TrialRepository>((ref) {
  return TrialRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
    ref.watch(licenseRepositoryProvider),
  );
});

/// The subscriber's state from the server; invalidate to resync (on resume,
/// after a request, every minute on the subscription screen).
final subscriptionStateProvider =
    FutureProvider.autoDispose<SubscriptionState>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(trialRepositoryProvider).subscriptionState();
});
