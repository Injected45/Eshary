import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/profit_report.dart';
import '../domain/treasury_position.dart';

/// The administrator's treasury (migration 0082). Live only: the costs move
/// with every entry, a cached figure would mislead.
class TreasuryRepository {
  TreasuryRepository(this._client);
  final SupabaseClient _client;

  Future<List<TreasuryPosition>> positions() async {
    final rows = await _client.rpc<dynamic>('treasury_positions');
    return (rows as List)
        .map((r) => TreasuryPosition.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Realized profit per account between [from] and [to] (migration 0084).
  Future<List<ProfitRow>> profitReport(DateTime from, DateTime to) async {
    final rows = await _client.rpc<dynamic>(
      'profit_report',
      params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return (rows as List)
        .map((r) => ProfitRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Every change of the account's cost, newest first.
  Future<List<CostEvent>> costHistory(String exchangeId) async {
    final rows = await _client.rpc<dynamic>(
      'account_cost_history',
      params: {'p_exchange_id': exchangeId},
    );
    return (rows as List)
        .map((r) => CostEvent.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The opening cost of the dollars the account holds now, or a correction.
  Future<void> setCost(String exchangeId, double rate) async {
    await _client.rpc<dynamic>(
      'set_account_cost',
      params: {'p_exchange_id': exchangeId, 'p_rate': rate},
    );
  }
}

final treasuryRepositoryProvider = Provider<TreasuryRepository>((ref) {
  return TreasuryRepository(ref.watch(supabaseClientProvider));
});
