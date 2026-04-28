import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../domain/currency_buy.dart';

class CurrencyBuysRepository {
  CurrencyBuysRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  String _cacheKey(CurrencyBuyStatus status) {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    return 'cache:currency_buys:$uid:${currencyBuyStatusToDb(status)}';
  }

  Future<List<CurrencyBuy>> listByStatus(CurrencyBuyStatus status) async {
    final key = _cacheKey(status);
    try {
      final rows = await _client
          .from('currency_buys')
          .select()
          .eq('status', currencyBuyStatusToDb(status))
          .order('created_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.writeList(key, list);
      return list.map(CurrencyBuy.fromJson).toList();
    } catch (e) {
      final cached = _cache.readList(key);
      if (cached == null) rethrow;
      return cached.map(CurrencyBuy.fromJson).toList();
    }
  }

  Future<CurrencyBuy> createDaily({
    required String myCompanyId,
    required String exchangeId,
    String? clientId,
    String? clientFromAccount,
    required double usdAmount,
    required double rate,
    required double lydAmount,
  }) async {
    final res = await _client.rpc(
      'record_currency_buy',
      params: {
        'p_my_company_id': myCompanyId,
        'p_exchange_id': exchangeId,
        'p_client_id': clientId,
        'p_client_from_account': clientFromAccount,
        'p_usd_amount': usdAmount,
        'p_rate': rate,
        'p_lyd_amount': lydAmount,
      },
    );
    return CurrencyBuy.fromJson(res as Map<String, dynamic>);
  }

  Future<CurrencyBuy> createPending({
    required String myCompanyId,
    required String exchangeId,
    String? clientId,
    String? clientFromAccount,
    required double usdAmount,
    required double rate,
    required double lydAmount,
  }) async {
    final res = await _client.rpc(
      'record_pending_buy',
      params: {
        'p_my_company_id': myCompanyId,
        'p_exchange_id': exchangeId,
        'p_client_id': clientId,
        'p_client_from_account': clientFromAccount,
        'p_usd_amount': usdAmount,
        'p_rate': rate,
        'p_lyd_amount': lydAmount,
      },
    );
    return CurrencyBuy.fromJson(res as Map<String, dynamic>);
  }

  Future<int> archiveDaily(String ownerId) async {
    final res = await _client.rpc(
      'archive_daily_buys',
      params: {'p_owner': ownerId},
    );
    return (res as num).toInt();
  }
}

final currencyBuysRepositoryProvider = Provider<CurrencyBuysRepository>((ref) {
  return CurrencyBuysRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
