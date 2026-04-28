import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../data/transfers_repository.dart';
import '../domain/transfer.dart';

final dailyTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  return ref.watch(transfersRepositoryProvider).listByStatus(TransferStatus.daily);
});

final archivedTransfersProvider = FutureProvider<List<Transfer>>((ref) async {
  return ref
      .watch(transfersRepositoryProvider)
      .listByStatus(TransferStatus.archived);
});

/// Action: archive all daily transfers for the current user.
/// Returns the number of rows archived. Throws if not signed in.
final archiveTransfersActionProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    final ownerId = ref.read(currentUserIdProvider);
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
