import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../currency_buy/data/currency_buys_repository.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/data/transfers_repository.dart';
import '../../transfers/presentation/transfers_providers.dart';

final archivedSoldTotalProvider = FutureProvider.autoDispose<double>((ref) async {
  final rows = await ref.watch(archivedTransfersProvider.future);
  return rows.fold<double>(0, (sum, t) => sum + t.netAmount);
});

final archivedBoughtTotalProvider = FutureProvider.autoDispose<double>((ref) async {
  final rows = await ref.watch(archivedBuysProvider.future);
  return rows.fold<double>(0, (sum, b) => sum + b.netAmount);
});

/// Whether anything was ever posted (the accounts tab's empty state): one row
/// from each table, never the history.
final hasArchivedOperationsProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final transfers = ref.watch(transfersRepositoryProvider);
  final buys = ref.watch(currencyBuysRepositoryProvider);
  return await transfers.hasArchived() || await buys.hasArchived();
});
