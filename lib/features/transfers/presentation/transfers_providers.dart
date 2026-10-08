import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../sub_users/domain/employee_permissions.dart';
import '../data/transfers_repository.dart';
import '../domain/transfer.dart';

final dailyTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(transfersRepositoryProvider).listByStatus(
        TransferStatus.daily,
        // An employee sees everyone's rows only with view_all;
        // otherwise only their own (the database enforces the same).
        createdByEmployeeId:
            (employee != null && !employee.permissions.contains(kPermViewAll))
                ? employee.subUserId
                : null,
      );
});

/// Exits executed today (posted at save), newest first. Emptied by the date
/// itself when a new day begins. An employee sees only their own unless they
/// may view everything.
final todayTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(transfersRepositoryProvider).listToday(
        createdByEmployeeId:
            (employee != null && !employee.permissions.contains(kPermViewAll))
                ? employee.subUserId
                : null,
      );
});

final archivedTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  final employee = ref.watch(currentEmployeeProvider).value;
  return ref.watch(transfersRepositoryProvider).listByStatus(
        TransferStatus.archived,
        createdByEmployeeId:
            (employee != null &&
                    !employee.permissions.contains(kPermViewAll) &&
                    !employee.permissions.contains(kPermClosingsAll))
                ? employee.subUserId
                : null,
      );
});
