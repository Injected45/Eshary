import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/exchange.dart';

class ExchangesRepository {
  ExchangesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Exchange>> listForCompany(String companyId) async {
    final rows = await _client
        .from('exchanges')
        .select()
        .eq('company_id', companyId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Exchange.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Exchange>> listAll() async {
    final rows = await _client
        .from('exchanges')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Exchange.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Opens an account (admin_open_account, migration 0087): the balance, its
  /// «رصيد افتتاحي» line and the opening cost [costRate] (dinars per dollar)
  /// in one transaction. An opening balance above 0 needs a cost; a direct
  /// insert with a balance is refused by the database.
  Future<Exchange> create({
    required String companyId,
    required String name,
    required double balance,
    String? ourCode,
    String? country,
    double? costRate,
    String? book,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'admin_open_account',
      params: {
        'p_company_id': companyId,
        'p_name': name,
        'p_balance': balance,
        'p_our_code': ourCode,
        'p_country': country,
        'p_cost_rate': costRate,
        // the book of the opening balance (0093)
        if (book != null) 'p_book': book,
      },
    );
    return Exchange.fromJson(row);
  }

  /// The account's name, code and country. Never its balance: a balance
  /// moves only through an operation or a documented adjustment (migration
  /// 0086 refuses a direct change). Sending back the balance read when the
  /// screen opened used to undo any operation saved meanwhile.
  Future<Exchange> update({
    required String id,
    required String name,
    String? ourCode,
    String? country,
  }) async {
    final row = await _client
        .from('exchanges')
        .update({
          'name': name,
          'our_code': ourCode,
          'country': country,
        })
        .eq('id', id)
        .select()
        .single();
    return Exchange.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('exchanges').delete().eq('id', id);
  }

  Future<bool> hasTransactions(String exchangeId) async {
    final transfers = await _client
        .from('transfers')
        .select('id')
        .eq('exchange_id', exchangeId)
        .limit(1);
    if ((transfers as List).isNotEmpty) return true;
    final buys = await _client
        .from('currency_buys')
        .select('id')
        .eq('exchange_id', exchangeId)
        .limit(1);
    return (buys as List).isNotEmpty;
  }
}

final exchangesRepositoryProvider = Provider<ExchangesRepository>((ref) {
  return ExchangesRepository(ref.watch(supabaseClientProvider));
});
