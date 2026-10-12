import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../trial/domain/trial_models.dart';

/// Deleting the signed-in account (Google Play requires this inside the app).
/// Two steps, both answered by the database: a code is sent by WhatsApp to the
/// phone registered on the account, and the right code deletes the account and
/// everything it owns for good.
class AccountDeletionRepository {
  AccountDeletionRepository(this._client);

  final SupabaseClient _client;

  /// Sends the code; returns the seconds before another may be requested.
  Future<int> requestCode() async {
    final res =
        await _client.rpc<Map<String, dynamic>>('account_delete_request');
    _throwIfRefused(res);
    return (res['wait'] as num?)?.toInt() ?? 60;
  }

  /// Deletes the account. After this the session is no longer valid.
  Future<void> confirm(String code) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'account_delete_confirm',
      params: {'p_code': code.trim()},
    );
    _throwIfRefused(res);
  }

  void _throwIfRefused(Map<String, dynamic> res) {
    if (res['ok'] == true) return;
    throw TrialRefused(
      (res['code'] as String?) ?? 'server_error',
      wait: (res['wait'] as num?)?.toInt(),
      left: (res['left'] as num?)?.toInt(),
    );
  }
}

final accountDeletionRepositoryProvider =
    Provider<AccountDeletionRepository>((ref) {
  return AccountDeletionRepository(ref.watch(supabaseClientProvider));
});
