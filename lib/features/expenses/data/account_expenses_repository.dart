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
    final rows = await _client
        .from('account_expenses')
        .select()
        .gte('created_at', start.toUtc().toIso8601String())
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => AccountExpense.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Deducts [amount] from the account, with the optional [code] and the
  /// [note] saying what it is for. Refused above the account's balance.
  Future<AccountExpense> record({
    required String exchangeId,
    required double amount,
    String? code,
    required String note,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'record_account_expense',
      params: {
        'p_exchange_id': exchangeId,
        'p_amount': amount,
        'p_code': code,
        'p_note': note,
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
