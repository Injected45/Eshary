import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/transfers_repository.dart';
import '../domain/transfer.dart';

// The history lists are autoDispose: read only while a screen that shows
// them is open (they used to be re-downloaded in full every minute, all day,
// on every phone).

final dailyTransfersProvider =
    FutureProvider.autoDispose<List<Transfer>>((ref) async {
  return ref.watch(transfersRepositoryProvider).listByStatus(
        TransferStatus.daily,
        // An employee sees everyone's rows only with view_all;
        // otherwise only their own (the database enforces the same).
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownRowsOf)),
      );
});

/// Exits executed today (posted at save), newest first. Emptied by the date
/// itself when a new day begins. An employee sees only their own unless they
/// may view everything.
final todayTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  return ref.watch(transfersRepositoryProvider).listToday(
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownRowsOf)),
      );
});

final archivedTransfersProvider =
    FutureProvider.autoDispose<List<Transfer>>((ref) async {
  return ref.watch(transfersRepositoryProvider).listByStatus(
        TransferStatus.archived,
        createdByEmployeeId:
            ref.watch(currentEmployeeProvider.select(ownArchiveRowsOf)),
      );
});
