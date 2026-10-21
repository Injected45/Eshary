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
    String? refPrefix,
  }) async {
    final row = await _client
        .from('clients')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'company': company,
          'code': code,
          // only sent when there is one, so a database without the column
          // (0069 not applied yet) still saves parties
          if ((refPrefix ?? '').trim().isNotEmpty)
            'ref_prefix': refPrefix!.trim(),
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
    bool updateRefPrefix = false,
    String? refPrefix,
  }) async {
    final row = await _client
        .from('clients')
        .update({
          'name': name,
          'company': company,
          'code': code,
          // the other callers (saving a first code) leave the letters alone
          if (updateRefPrefix)
            'ref_prefix':
                (refPrefix ?? '').trim().isEmpty ? null : refPrefix!.trim(),
        })
        .eq('id', id)
        .select()
        .single();
    return Client.fromJson(row);
  }

  /// An employee granted "party_letters" sets only the letters of a sender's
  /// reference numbers (migration 0071); the party itself stays untouched.
  Future<void> setPartyLetters(String id, String letters) async {
    await _client.rpc<void>(
      'employee_set_party_letters',
      params: {'p_client_id': id, 'p_letters': letters},
    );
  }

  Future<void> delete(String id) async {
    final usage = await _client
        .from('currency_buys')
        .select('id')
        .eq('client_id', id)
        .limit(1);
    if ((usage as List).isNotEmpty) {
      throw const ClientHasOperationsException();
    }
    await _client.from('clients').delete().eq('id', id);
  }
}

class ClientHasOperationsException implements Exception {
  const ClientHasOperationsException();
  @override
  String toString() => 'client_has_operations';
}

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  return ClientsRepository(ref.watch(supabaseClientProvider));
});
