import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../cancellations/domain/cancellation.dart';
import '../domain/account_expense.dart';

/// Reads and writes the account expenses (migration 0072). Writing goes only
/// through the database functions: the balance moves in the same transaction.
class AccountExpensesRepository {
  AccountExpensesRepository(this._client);
  final SupabaseClient _client;

  /// Every expense recorded since [start], oldest first.
  Future<List<AccountExpense>> listSince(DateTime start) async {
    // page by page: a statement's opening balance needs every one
    const page = 1000;
    final out = <AccountExpense>[];
    for (var from = 0;; from += page) {
      final rows = await _client
          .from('account_expenses')
          .select()
          .gte('created_at', start.toUtc().toIso8601String())
          .order('created_at', ascending: true)
          .order('id')
          .range(from, from + page - 1);
      final chunk = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(chunk.map(AccountExpense.fromJson));
      if (chunk.length < page) break;
    }
    return out;
  }

  /// Deducts [amount] from the account, with the optional [code] and the
  /// [note] saying what it is for. Refused above the account's balance.
  Future<AccountExpense> record({
    required String exchangeId,
    required double amount,
    String? code,
    required String note,
    String? book,
    String? requestId,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'record_account_expense',
      params: {
        'p_exchange_id': exchangeId,
        'p_amount': amount,
        'p_code': code,
        'p_note': note,
        // the book the dollars leave (0093)
        if (book != null) 'p_book': book,
        // the same request again is not taken twice (0094)
        if (requestId != null) 'p_request_id': requestId,
      },
    );
    return AccountExpense.fromJson(row);
  }

  /// Cancels an expense of today with the administrator's password. A wrong
  /// password is returned (counted for the lock), not thrown.
  Future<CancelResult> cancel(
    String id, {
    required String reason,
    required String password,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_cancel_expense',
      params: {'p_expense_id': id, 'p_reason': reason, 'p_password': password},
    );
    return parseCancelResult(res);
  }
}

final accountExpensesRepositoryProvider =
    Provider<AccountExpensesRepository>((ref) {
  return AccountExpensesRepository(ref.watch(supabaseClientProvider));
});

/// The expenses recorded today (by the phone's date), for the commission
/// dialog: the ones that can still be cancelled.
final todayExpensesProvider = FutureProvider<List<AccountExpense>>((ref) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  return ref.watch(accountExpensesRepositoryProvider).listSince(startOfDay);
});
