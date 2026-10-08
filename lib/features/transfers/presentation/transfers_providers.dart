import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
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

/// Action: archive all daily transfers for the current user.
/// Returns the number of rows archived. Throws if not signed in.
final archiveTransfersActionProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    // An employee closes the day for the admin who owns the data.
    final ownerId = ref.read(currentEmployeeProvider).value?.parentAdminId ??
        ref.read(currentUserIdProvider);
    if (ownerId == null) {
      throw StateError('not signed in');
    }
    final count =
        await ref.read(transfersRepositoryProvider).archiveDaily(ownerId);
    ref.invalidate(dailyTransfersProvider);
    ref.invalidate(archivedTransfersProvider);
    return count;
  };
});
