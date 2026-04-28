import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/company.dart';

class CompaniesRepository {
  CompaniesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Company>> list() async {
    final rows = await _client
        .from('companies')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Company.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Company> create({
    required String ownerId,
    required String name,
    required String startRef,
  }) async {
    final row = await _client
        .from('companies')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'start_ref': startRef,
        })
        .select()
        .single();
    return Company.fromJson(row);
  }

  Future<Company> update({
    required String id,
    required String name,
    required String startRef,
  }) async {
    final row = await _client
        .from('companies')
        .update({'name': name, 'start_ref': startRef})
        .eq('id', id)
        .select()
        .single();
    return Company.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('companies').delete().eq('id', id);
  }

  Future<String> nextReference(String companyId) async {
    final res = await _client.rpc(
      'next_reference',
      params: {'p_company_id': companyId},
    );
    return res as String;
  }
}

final companiesRepositoryProvider = Provider<CompaniesRepository>((ref) {
  return CompaniesRepository(ref.watch(supabaseClientProvider));
});
