import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';

// The history lists are autoDispose: read only while a screen that shows
// them is open (see transfers_providers.dart).

final dailyBuysProvider =
    FutureProvider.autoDispose<List<CurrencyBuy>>((ref) async {
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.daily,
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownRowsOf)),
      );
});

/// Entries executed today (posted at save), newest first; see
/// [todayTransfersProvider].
final todayBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  return ref.watch(currencyBuysRepositoryProvider).listToday(
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownRowsOf)),
      );
});

final pendingBuysProvider =
    FutureProvider.autoDispose<List<CurrencyBuy>>((ref) async {
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.pending,
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownRowsOf)),
      );
});

final archivedBuysProvider =
    FutureProvider.autoDispose<List<CurrencyBuy>>((ref) async {
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.archived,
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownArchiveRowsOf)),
      );
});
