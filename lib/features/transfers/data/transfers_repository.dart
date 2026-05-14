import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../domain/transfer.dart';

class TransfersRepository {
  TransfersRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  String _cacheKey(TransferStatus status, String? createdByEmployeeId) {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    final suffix = createdByEmployeeId == null ? '' : ':emp:$createdByEmployeeId';
    return 'cache:transfers:$uid:${transferStatusToDb(status)}$suffix';
  }

  /// When [createdByEmployeeId] is non-null the result is scoped to rows
  /// the given sub_user authored — used by the employee app so each
  /// employee only sees their own daily / archived operations even though
  /// RLS would otherwise expose every sibling employee's record.
  Future<List<Transfer>> listByStatus(
    TransferStatus status, {
    String? createdByEmployeeId,
  }) async {
    final key = _cacheKey(status, createdByEmployeeId);
    try {
      var filter = _client
          .from('transfers')
          .select()
          .eq('status', transferStatusToDb(status));
      if (createdByEmployeeId != null) {
        filter = filter.eq('created_by_employee_id', createdByEmployeeId);
      }
      final rows = await filter.order('created_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.writeList(key, list);
      return list.map(Transfer.fromJson).toList();
    } catch (e) {
      final cached = _cache.readList(key);
      if (cached == null) rethrow;
      return cached.map(Transfer.fromJson).toList();
    }
  }

  Future<Transfer> create({
    required String companyId,
    required String exchangeId,
    required String beneficiaryName,
    String? beneficiaryAccountCompany,
    String? beneficiaryCode,
    required double amount,
    required String reference,
  }) async {
    final res = await _client.rpc(
      'record_transfer',
      params: {
        'p_company_id': companyId,
        'p_exchange_id': exchangeId,
        'p_beneficiary_name': beneficiaryName,
        'p_beneficiary_account_company': beneficiaryAccountCompany,
        'p_beneficiary_code': beneficiaryCode,
        'p_amount': amount,
        'p_reference': reference,
      },
    );
    return Transfer.fromJson(res as Map<String, dynamic>);
  }

  Future<int> archiveDaily(String ownerId) async {
    final res = await _client.rpc(
      'archive_daily_transfers',
      params: {'p_owner': ownerId},
    );
    return (res as num).toInt();
  }
}

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return TransfersRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
