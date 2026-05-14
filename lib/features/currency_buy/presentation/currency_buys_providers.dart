import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';

final dailyBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.daily,
        createdByEmployeeId: employee?.subUserId,
      );
});

final pendingBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.pending,
        createdByEmployeeId: employee?.subUserId,
      );
});

final archivedBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.archived,
        createdByEmployeeId: employee?.subUserId,
      );
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
