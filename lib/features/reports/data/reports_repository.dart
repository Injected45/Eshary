import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/reports.dart';

/// The administrator's reports (migration 0095), added up by the database.
class ReportsRepository {
  ReportsRepository(this._client);
  final SupabaseClient _client;

  Future<PeriodReport> period(DateTime from, DateTime to) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'report_period',
      params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    return PeriodReport.fromJson(res);
  }

  Future<DebtAging> debtAging() async {
    final res = await _client.rpc<Map<String, dynamic>>('report_debt_aging');
    return DebtAging.fromJson(res);
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

/// Keyed by a range the screen keeps (never one built from "now" on every
/// rebuild: a new key would reload for ever).
final periodReportProvider = FutureProvider.autoDispose
    .family<PeriodReport, DateTimeRange>((ref, range) {
  return ref.watch(reportsRepositoryProvider).period(range.start, range.end);
});

final debtAgingProvider = FutureProvider.autoDispose<DebtAging>((ref) {
  return ref.watch(reportsRepositoryProvider).debtAging();
});
