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

  Future<Exchange> create({
    required String companyId,
    required String name,
    required double balance,
    String? ourCode,
    String? country,
  }) async {
    final row = await _client
        .from('exchanges')
        .insert({
          'company_id': companyId,
          'name': name,
          'balance': balance,
          'our_code': ourCode,
          'country': country,
        })
        .select()
        .single();
    return Exchange.fromJson(row);
  }

  Future<Exchange> update({
    required String id,
    required String name,
    required double balance,
    String? ourCode,
    String? country,
  }) async {
    final row = await _client
        .from('exchanges')
        .update({
          'name': name,
          'balance': balance,
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

  Future<Exchange> updateBalance(String exchangeId, double newBalance) async {
    final row = await _client
        .from('exchanges')
        .update({'balance': newBalance})
        .eq('id', exchangeId)
        .select()
        .single();
    return Exchange.fromJson(row);
  }
}

final exchangesRepositoryProvider = Provider<ExchangesRepository>((ref) {
  return ExchangesRepository(ref.watch(supabaseClientProvider));
});
