import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';

/// What a wipe removed (`owner_wipe_operations`, 0054), or why it removed
/// nothing: since 0087 it asks for the administrator's password.
class WipeResult {
  const WipeResult({
    required this.transfers,
    required this.currencyBuys,
    required this.cancellations,
    this.error,
    this.remaining = 0,
  });
  final int transfers;
  final int currencyBuys;
  final int cancellations;

  /// null when done; else 'wrong_password', 'locked' or 'password_not_set'.
  final String? error;

  /// Tries left before the password locks for 15 minutes.
  final int remaining;

  bool get ok => error == null;
  int get total => transfers + currencyBuys;

  factory WipeResult.fromJson(Map<String, dynamic> j) => WipeResult(
        transfers: (j['transfers'] as num?)?.toInt() ?? 0,
        currencyBuys: (j['currency_buys'] as num?)?.toInt() ?? 0,
        cancellations: (j['cancellations'] as num?)?.toInt() ?? 0,
        error: j['ok'] == false ? (j['error'] as String? ?? 'failed') : null,
        remaining: (j['remaining'] as num?)?.toInt() ?? 0,
      );
}

/// "حذف المدخلات": deletes every financial operation of the account in one
/// database transaction (after saving a safety backup), with everything that
/// depends on them (costs, adjustments, the dinar treasury), and puts the
/// balances back to 0. The numbering of references goes on after the last
/// number used (0087). Since 0048 the API refuses direct deletes, so this is
/// the only way.
class WipeRepository {
  WipeRepository(this._client);
  final SupabaseClient _client;

  Future<WipeResult> wipeOperations(String password) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'owner_wipe_operations',
      params: {'p_password': password},
    );
    return WipeResult.fromJson(res);
  }
}

final wipeRepositoryProvider = Provider<WipeRepository>((ref) {
  return WipeRepository(ref.watch(supabaseClientProvider));
});
