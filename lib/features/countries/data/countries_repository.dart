import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/country.dart';

class CountriesRepository {
  CountriesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Country>> list() async {
    final rows = await _client
        .from('countries')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Country.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Country> create({
    required String ownerId,
    required String name,
  }) async {
    final row = await _client
        .from('countries')
        .insert({'owner_id': ownerId, 'name': name})
        .select()
        .single();
    return Country.fromJson(row);
  }

  Future<Country> update({
    required String id,
    required String name,
  }) async {
    final row = await _client
        .from('countries')
        .update({'name': name})
        .eq('id', id)
        .select()
        .single();
    return Country.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('countries').delete().eq('id', id);
  }
}

final countriesRepositoryProvider = Provider<CountriesRepository>((ref) {
  return CountriesRepository(ref.watch(supabaseClientProvider));
});
