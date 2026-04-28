import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/exchange_company.dart';

class ExchangeCompaniesRepository {
  ExchangeCompaniesRepository(this._client);
  final SupabaseClient _client;

  Future<List<ExchangeCompany>> list() async {
    final rows = await _client
        .from('exchange_companies')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => ExchangeCompany.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ExchangeCompany> create({
    required String ownerId,
    required String name,
    String? country,
  }) async {
    final row = await _client
        .from('exchange_companies')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'country': country,
        })
        .select()
        .single();
    return ExchangeCompany.fromJson(row);
  }

  Future<ExchangeCompany> update({
    required String id,
    required String name,
    String? country,
  }) async {
    final row = await _client
        .from('exchange_companies')
        .update({
          'name': name,
          'country': country,
        })
        .eq('id', id)
        .select()
        .single();
    return ExchangeCompany.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('exchange_companies').delete().eq('id', id);
  }
}

final exchangeCompaniesRepositoryProvider =
    Provider<ExchangeCompaniesRepository>((ref) {
  return ExchangeCompaniesRepository(ref.watch(supabaseClientProvider));
});
