import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';

final archivedSoldTotalProvider = FutureProvider<double>((ref) async {
  final rows = await ref.watch(archivedTransfersProvider.future);
  return rows.fold<double>(0, (sum, t) => sum + t.amount);
});

final archivedBoughtTotalProvider = FutureProvider<double>((ref) async {
  final rows = await ref.watch(archivedBuysProvider.future);
  return rows.fold<double>(0, (sum, b) => sum + b.usdAmount);
});
