import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/balance_adjustment.dart';

class AdjustmentsRepository {
  AdjustmentsRepository(this._client);
  final SupabaseClient _client;

  /// The administrator's adjustments since [start] (RLS: his own only).
  Future<List<BalanceAdjustment>> listSince(DateTime start) async {
    final rows = await _client
        .from('balance_adjustments')
        .select()
        .gte('created_at', start.toUtc().toIso8601String())
        .order('created_at');
    return (rows as List)
        .map((r) => BalanceAdjustment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<AdjustResult> adjust({
    required String exchangeId,
    required double newBalance,
    required String reason,
    required String password,
  }) async {
    final res = await _client.rpc<dynamic>(
      'admin_adjust_balance',
      params: {
        'p_exchange_id': exchangeId,
        'p_new_balance': newBalance,
        'p_reason': reason,
        'p_password': password,
      },
    );
    return parseAdjustResult(res as Map<String, dynamic>);
  }
}

final adjustmentsRepositoryProvider = Provider<AdjustmentsRepository>((ref) {
  return AdjustmentsRepository(ref.watch(supabaseClientProvider));
});
