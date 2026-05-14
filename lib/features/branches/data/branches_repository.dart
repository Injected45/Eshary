import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/branch.dart';

class BranchesRepository {
  BranchesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Branch>> list() async {
    final rows = await _client
        .from('branches')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Branch.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Branch> create({
    required String parentAdminId,
    required String name,
  }) async {
    final row = await _client
        .from('branches')
        .insert({
          'parent_admin_id': parentAdminId,
          'name': name,
        })
        .select()
        .single();
    return Branch.fromJson(row);
  }

  Future<Branch> update({
    required String id,
    required String name,
  }) async {
    final row = await _client
        .from('branches')
        .update({'name': name})
        .eq('id', id)
        .select()
        .single();
    return Branch.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('branches').delete().eq('id', id);
  }
}

final branchesRepositoryProvider = Provider<BranchesRepository>((ref) {
  return BranchesRepository(ref.watch(supabaseClientProvider));
});
