import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../sub_users/domain/employee_permissions.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';

final dailyBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.daily,
        createdByEmployeeId:
            (employee != null && !employee.permissions.contains(kPermViewAll))
                ? employee.subUserId
                : null,
      );
});

/// Entries executed today (posted at save), newest first; see
/// [todayTransfersProvider].
final todayBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listToday(
        createdByEmployeeId:
            (employee != null && !employee.permissions.contains(kPermViewAll))
                ? employee.subUserId
                : null,
      );
});

final pendingBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.pending,
        createdByEmployeeId:
            (employee != null && !employee.permissions.contains(kPermViewAll))
                ? employee.subUserId
                : null,
      );
});

final archivedBuysProvider = FutureProvider<List<CurrencyBuy>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(currencyBuysRepositoryProvider).listByStatus(
        CurrencyBuyStatus.archived,
        createdByEmployeeId:
            (employee != null &&
                    !employee.permissions.contains(kPermViewAll) &&
                    !employee.permissions.contains(kPermClosingsAll))
                ? employee.subUserId
                : null,
      );
});
