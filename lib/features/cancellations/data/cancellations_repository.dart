import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/cancellation.dart';

/// Cancelling operations entered by mistake (0048_cancellations.sql). Every
/// write goes through a database function that checks who is asking, the
/// password, the day and the balance; nothing here is cached offline.
class CancellationsRepository {
  CancellationsRepository(this._client);
  final SupabaseClient _client;

  /// Admin: cancel [operationId] after typing the account password. A wrong
  /// password / lock comes back as a [CancelResult]; any other refusal
  /// (day passed, already cancelled, balance) is thrown.
  Future<CancelResult> cancel({
    required OperationKind kind,
    required String operationId,
    required String reason,
    required String password,
    String? requestId,
  }) async {
    final res = await _client.rpc<dynamic>(
      'admin_cancel_operation',
      params: {
        'p_kind': operationKindToDb(kind),
        'p_operation_id': operationId,
        'p_reason': reason,
        'p_password': password,
        'p_request_id': requestId,
      },
    );
    return parseCancelResult(Map<String, dynamic>.from(res as Map));
  }

  /// Employee: ask the admin to cancel one of their own operations of today.
  Future<void> request({
    required OperationKind kind,
    required String operationId,
    required String reason,
  }) async {
    await _client.rpc<dynamic>(
      'employee_request_cancellation',
      params: {
        'p_kind': operationKindToDb(kind),
        'p_operation_id': operationId,
        'p_reason': reason,
      },
    );
  }

  /// Admin: refuse a request (the employee is told).
  Future<void> reject(String requestId, {String? note}) async {
    await _client.rpc<dynamic>(
      'admin_reject_cancellation',
      params: {'p_request_id': requestId, 'p_note': note},
    );
  }

  /// Requests, newest first. The admin gets every employee's; an employee
  /// only their own (row-level security).
  Future<List<CancellationRequest>> listRequests() async {
    final rows = await _client
        .from('cancellation_requests')
        .select()
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List)
        .map((r) => CancellationRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Admin: the cancellations made between [start] and [end], oldest first.
  Future<List<OperationCancellation>> listBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _client
        .from('operation_cancellations')
        .select()
        .gte('cancelled_at', start.toUtc().toIso8601String())
        .lte('cancelled_at', end.toUtc().toIso8601String())
        .order('cancelled_at', ascending: true);
    return (rows as List)
        .map((r) => OperationCancellation.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final cancellationsRepositoryProvider =
    Provider<CancellationsRepository>((ref) {
  return CancellationsRepository(ref.watch(supabaseClientProvider));
});
