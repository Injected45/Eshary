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
    String? requestId,
  }) async {
    await _client.rpc<dynamic>(
      'move_between_books',
      params: {
        'p_exchange_id': exchangeId,
        'p_from': from,
        'p_usd': usd,
        'p_price': price,
        'p_note': note,
        // the same request again is not saved twice (0094)
        if (requestId != null) 'p_request_id': requestId,
      },
    );
  }

  /// «رصيد أول المدة» (0094): the first [usd] dollars of a [book] that never
  /// moved, at [cost] dinars of that book per dollar — dollars at cost
  /// against capital, as when an account is opened with a balance. Once per
  /// book (opening_already_set); an account still holding dollars from before
  /// 0093 is split first (books_not_split).
  Future<void> setOpening({
    required String exchangeId,
    required String book,
    required double usd,
    required double cost,
  }) async {
    await _client.rpc<dynamic>(
      'admin_set_opening',
      params: {
        'p_exchange_id': exchangeId,
        'p_book': book,
        'p_usd': usd,
        'p_cost': cost,
      },
    );
  }
}

final accountBooksRepositoryProvider = Provider<AccountBooksRepository>((ref) {
  return AccountBooksRepository(ref.watch(supabaseClientProvider));
});
