import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/client.dart';

class ClientsRepository {
  ClientsRepository(this._client);
  final SupabaseClient _client;

  Future<List<Client>> list() async {
    final rows = await _client
        .from('clients')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Client.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Client> create({
    required String ownerId,
    required String name,
    String? company,
    String? code,
  }) async {
    final row = await _client
        .from('clients')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'company': company,
          'code': code,
        })
        .select()
        .single();
    return Client.fromJson(row);
  }

  Future<Client> update({
    required String id,
    required String name,
    String? company,
    String? code,
  }) async {
    final row = await _client
        .from('clients')
        .update({
          'name': name,
          'company': company,
          'code': code,
        })
        .eq('id', id)
        .select()
        .single();
    return Client.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }
}

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  return ClientsRepository(ref.watch(supabaseClientProvider));
});
