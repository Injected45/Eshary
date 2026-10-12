import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/trial_models.dart';

/// The administrator's side: requests, decisions, subscription actions. Every
/// rule (7-day approval, extension from max(now, end), reasons required) is in
/// the database; the screens only ask.
class TrialAdminRepository {
  TrialAdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<TrialRequestRow>> list() async {
    final res = await _client.rpc<List<dynamic>>('admin_list_trial_requests');
    return res
        .cast<Map<String, dynamic>>()
        .map(TrialRequestRow.fromJson)
        .toList();
  }

  /// approve_72 | approve_168 | request_info | reject | withdraw |
  /// renew_approval
  /// Returns what the database answered (for an approval: whether the WhatsApp
  /// code was queued).
  Future<Map<String, dynamic>> decide(
    String id,
    String decision, {
    String? note,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_trial_decide',
      params: {'p_id': id, 'p_decision': decision, 'p_note': note},
    );
    return res;
  }

  Future<PendingCounts> pendingCounts() async {
    final res = await _client.rpc<Map<String, dynamic>>('admin_pending_counts');
    return PendingCounts.fromJson(res);
  }

  Future<void> fixPhone(String id, String phone) async {
    await _client.rpc<dynamic>(
      'admin_trial_fix_phone',
      params: {'p_id': id, 'p_phone': phone},
    );
  }

  Future<void> resendCode(String id) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_resend_trial_code',
      params: {'p_id': id},
    );
    if (res['ok'] != true) {
      throw TrialRefused(
        (res['code'] as String?) ?? 'send_failed',
        wait: (res['wait'] as num?)?.toInt(),
      );
    }
  }

  /// extend_trial (hours, reason) | confirm_payment (days, reference) |
  /// suspend (reason) | reactivate
  Future<void> subscriptionAction(
    String userId,
    String action, {
    int? hours,
    int? days,
    String? reference,
    String? reason,
  }) async {
    await _client.rpc<dynamic>(
      'admin_subscription_action',
      params: {
        'p_user': userId,
        'p_action': action,
        'p_hours': hours,
        'p_days': days,
        'p_reference': reference,
        'p_reason': reason,
      },
    );
  }

  Future<List<Map<String, dynamic>>> phoneChanges() async {
    final res = await _client.rpc<List<dynamic>>('admin_list_phone_changes');
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> decidePhoneChange(String id, bool approve,
      {String? note}) async {
    await _client.rpc<dynamic>(
      'admin_phone_change_decide',
      params: {'p_id': id, 'p_approve': approve, 'p_note': note},
    );
  }

  Future<Map<String, dynamic>> stats() async {
    return _client.rpc<Map<String, dynamic>>('admin_trial_stats');
  }

  Future<List<Map<String, dynamic>>> audit({String? subject}) async {
    final res = await _client.rpc<List<dynamic>>(
      'admin_list_audit',
      params: {'p_limit': 200, 'p_subject': subject},
    );
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> alerts() async {
    final res = await _client.rpc<List<dynamic>>('admin_platform_alerts');
    return res.cast<Map<String, dynamic>>();
  }
}

final trialAdminRepositoryProvider = Provider<TrialAdminRepository>((ref) {
  return TrialAdminRepository(ref.watch(supabaseClientProvider));
});

final trialRequestsProvider =
    FutureProvider.autoDispose<List<TrialRequestRow>>((ref) async {
  return ref.watch(trialAdminRepositoryProvider).list();
});

final trialStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(trialAdminRepositoryProvider).stats();
});

/// How many things wait for the administrator, re-read every 45 seconds while
/// something is watching it (the badge in Settings, the banner in the accounts
/// screen). A failed read counts as "nothing", never as an error on screen.
final adminPendingCountsProvider =
    StreamProvider.autoDispose<PendingCounts>((ref) async* {
  final repo = ref.watch(trialAdminRepositoryProvider);
  while (true) {
    try {
      yield await repo.pendingCounts();
    } catch (_) {
      yield PendingCounts.zero;
    }
    await Future<void>.delayed(const Duration(seconds: 45));
  }
});
