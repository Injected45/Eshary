import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/treasury_repository.dart';
import '../domain/profit_report.dart';
import '../domain/treasury_position.dart';

/// Read again every time the treasury opens.
final treasuryProvider =
    FutureProvider.autoDispose<List<TreasuryPosition>>((ref) {
  return ref.watch(treasuryRepositoryProvider).positions();
});

/// The account's cost for the exit / entry screens: the administrator only
/// (an employee never sees a cost; the database refuses it anyway). Empty
/// for an employee or when it cannot be read.
final accountCostsProvider =
    FutureProvider.autoDispose<Map<String, TreasuryPosition>>((ref) async {
  if (ref.watch(isEmployeeProvider)) return const {};
  try {
    final rows = await ref.watch(treasuryRepositoryProvider).positions();
    return {for (final p in rows) p.exchangeId: p};
  } catch (_) {
    return const {};
  }
});

final profitReportProvider = FutureProvider.autoDispose
    .family<List<ProfitRow>, DateTimeRange>((ref, range) {
  return ref
      .watch(treasuryRepositoryProvider)
      .profitReport(range.start, range.end);
});

final costHistoryProvider = FutureProvider.autoDispose
    .family<List<CostEvent>, String>((ref, exchangeId) {
  return ref.watch(treasuryRepositoryProvider).costHistory(exchangeId);
});
