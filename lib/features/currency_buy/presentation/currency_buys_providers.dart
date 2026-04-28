import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';

final dailyBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  return ref
      .watch(currencyBuysRepositoryProvider)
      .listByStatus(CurrencyBuyStatus.daily);
});

final pendingBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  return ref
      .watch(currencyBuysRepositoryProvider)
      .listByStatus(CurrencyBuyStatus.pending);
});

final archivedBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  return ref
      .watch(currencyBuysRepositoryProvider)
      .listByStatus(CurrencyBuyStatus.archived);
});

/// Action: archive all daily currency buys. Server raises if any are pending.
final archiveBuysActionProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    final ownerId = ref.read(currentUserIdProvider);
    if (ownerId == null) {
      throw StateError('not signed in');
    }
    final count =
        await ref.read(currencyBuysRepositoryProvider).archiveDaily(ownerId);
    ref.invalidate(dailyBuysProvider);
    ref.invalidate(archivedBuysProvider);
    ref.invalidate(pendingBuysProvider);
    return count;
  };
});
