import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cancellations_repository.dart';
import '../domain/cancellation.dart';

/// Every cancellation request visible to the caller, newest first.
final cancelRequestsProvider =
    FutureProvider<List<CancellationRequest>>((ref) {
  return ref.watch(cancellationsRepositoryProvider).listRequests();
});

/// Requests still waiting for the admin today.
final pendingCancelRequestsProvider =
    Provider<List<CancellationRequest>>((ref) {
  final all = ref.watch(cancelRequestsProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return [
    for (final r in all)
      if (r.isPending && !r.isExpiredAt(now)) r,
  ];
});

/// The open request for one operation, if any.
final pendingRequestForProvider =
    Provider.family<CancellationRequest?, String>((ref, operationId) {
  return ref
      .watch(pendingCancelRequestsProvider)
      .where((r) => r.operationId == operationId)
      .firstOrNull;
});

/// كشف الإلغاءات for a period.
final cancellationsBetweenProvider = FutureProvider.autoDispose
    .family<List<OperationCancellation>, DateTimeRange>((ref, range) {
  return ref
      .watch(cancellationsRepositoryProvider)
      .listBetween(range.start, range.end);
});
