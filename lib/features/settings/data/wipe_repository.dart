import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';

/// What a wipe removed (`owner_wipe_operations`, 0054).
class WipeResult {
  const WipeResult({
    required this.transfers,
    required this.currencyBuys,
    required this.cancellations,
  });
  final int transfers;
  final int currencyBuys;
  final int cancellations;

  int get total => transfers + currencyBuys;

  factory WipeResult.fromJson(Map<String, dynamic> j) => WipeResult(
        transfers: (j['transfers'] as num?)?.toInt() ?? 0,
        currencyBuys: (j['currency_buys'] as num?)?.toInt() ?? 0,
        cancellations: (j['cancellations'] as num?)?.toInt() ?? 0,
      );
}

/// "حذف المدخلات": deletes every financial operation of the account in one
/// database transaction (after saving a safety backup) and puts the balances
/// back to 0. Since 0048 the API refuses direct deletes, so this is the only way.
class WipeRepository {
  WipeRepository(this._client);
  final SupabaseClient _client;

  Future<WipeResult> wipeOperations() async {
    final res = await _client.rpc<Map<String, dynamic>>('owner_wipe_operations');
    return WipeResult.fromJson(res);
  }
}

final wipeRepositoryProvider = Provider<WipeRepository>((ref) {
  return WipeRepository(ref.watch(supabaseClientProvider));
});
