import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/account_books_repository.dart';
import '../data/treasury_repository.dart';
import '../domain/account_books.dart';
import '../domain/lyd_treasury.dart';
import '../domain/profit_report.dart';
import '../domain/treasury_position.dart';

/// Read again every time the treasury opens.
final treasuryProvider =
    FutureProvider.autoDispose<List<TreasuryPosition>>((ref) {
  return ref.watch(treasuryRepositoryProvider).positions();
});

/// The account's cost for the exit / entry screens: the administrator only
/// (an employee never sees a cost; the database refuses it anyway). Empty for
/// an employee. A failed read stays an error, so the exit screen can say the
/// cost could not be checked instead of skipping the below-cost warning.
final accountCostsProvider =
    FutureProvider.autoDispose<Map<String, TreasuryPosition>>((ref) async {
  if (ref.watch(isEmployeeProvider)) return const {};
  final rows = await ref.watch(treasuryRepositoryProvider).positions();
  return {for (final p in rows) p.exchangeId: p};
});

/// Each account's cash and bank books (0093), for the sale and purchase
/// screens (the cost of the operation's book) and the treasury. The
/// administrator only; empty for an employee; a failed read stays an error.
final accountBooksProvider =
    FutureProvider.autoDispose<Map<String, AccountBooks>>((ref) async {
  if (ref.watch(isEmployeeProvider)) return const {};
  final rows = await ref.watch(accountBooksRepositoryProvider).list();
  return {for (final b in rows) b.exchangeId: b};
});

final profitReportProvider = FutureProvider.autoDispose
    .family<List<ProfitRow>, DateTimeRange>((ref, range) {
  return ref
      .watch(treasuryRepositoryProvider)
      .profitReport(range.start, range.end);
});

final lydSummaryProvider =
    FutureProvider.autoDispose.family<LydSummary, DateTimeRange>((ref, range) {
  return ref
      .watch(treasuryRepositoryProvider)
      .lydSummary(range.start, range.end);
});

final costHistoryProvider = FutureProvider.autoDispose
    .family<List<CostEvent>, String>((ref, exchangeId) {
  return ref.watch(treasuryRepositoryProvider).costHistory(exchangeId);
});
