import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/beneficiary.dart';

class BeneficiariesRepository {
  BeneficiariesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Beneficiary>> list() async {
    final rows = await _client
        .from('beneficiaries')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Beneficiary.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Beneficiary> create({
    required String ownerId,
    required String name,
    String? account,
    String? code,
  }) async {
    final row = await _client
        .from('beneficiaries')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'account': account,
          'code': code,
        })
        .select()
        .single();
    return Beneficiary.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('beneficiaries').delete().eq('id', id);
  }
}

final beneficiariesRepositoryProvider =
    Provider<BeneficiariesRepository>((ref) {
  return BeneficiariesRepository(ref.watch(supabaseClientProvider));
});
