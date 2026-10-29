import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/account_books.dart';

/// The cash and bank books of each account (migration 0093). The
/// administrator only: the database refuses an employee.
class AccountBooksRepository {
  AccountBooksRepository(this._client);
  final SupabaseClient _client;

  Future<List<AccountBooks>> list() async {
    final res = await _client.rpc<List<dynamic>>('account_books_list');
    return res.cast<Map<String, dynamic>>().map(AccountBooks.fromJson).toList();
  }

  /// Splits the dollars an account held before 0093, once: [cashQty] into
  /// the cash book at [cashCost], the rest into the bank book at [bankCost].
  Future<void> split({
    required String exchangeId,
    required double cashQty,
    double? cashCost,
    double? bankCost,
  }) async {
    await _client.rpc<dynamic>(
      'set_account_books',
      params: {
        'p_exchange_id': exchangeId,
        'p_cash_qty': cashQty,
        'p_cash_cost': cashCost,
        'p_bank_cost': bankCost,
      },
    );
  }

  /// Moves [usd] dollars out of the [from] book (at its cost) into the other
  /// one at [price] dinars (of that book) per dollar.
  Future<void> move({
    required String exchangeId,
    required String from,
    required double usd,
    required double price,
    String? note,
  }) async {
    await _client.rpc<dynamic>(
      'move_between_books',
      params: {
        'p_exchange_id': exchangeId,
        'p_from': from,
        'p_usd': usd,
        'p_price': price,
        'p_note': note,
      },
    );
  }
}

final accountBooksRepositoryProvider = Provider<AccountBooksRepository>((ref) {
  return AccountBooksRepository(ref.watch(supabaseClientProvider));
});
