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

  /// Today's executed exits (posted at save). "Today" is the phone's local
  /// date, so the list empties by itself when a new day begins.
  Future<List<Transfer>> listToday({String? createdByEmployeeId}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final key =
        '${_cacheKey(TransferStatus.archived, createdByEmployeeId)}:today';
    try {
      var filter = _client
          .from('transfers')
          .select()
          .eq('status', transferStatusToDb(TransferStatus.archived))
          .gte('created_at', start.toIso8601String());
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
      final today = start.toLocal();
      return cached
          .map(Transfer.fromJson)
          .where((t) => !t.createdAt.toLocal().isBefore(today))
          .toList();
    }
  }

  /// Every posted exit in [start]..[end] (by posting time), oldest first, for
  /// a statement. Fetched page by page: one request returns at most 1000 rows,
  /// and a statement must not be cut short silently.
  Future<List<Transfer>> listArchivedBetween(
    DateTime start,
    DateTime end,
  ) async {
    const page = 1000;
    final out = <Transfer>[];
    for (var from = 0;; from += page) {
      final rows = await _client
          .from('transfers')
          .select()
          .eq('status', transferStatusToDb(TransferStatus.archived))
          .gte('archived_at', start.toUtc().toIso8601String())
          .lte('archived_at', end.toUtc().toIso8601String())
          .order('archived_at', ascending: true)
          .order('id')
          .range(from, from + page - 1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(list.map(Transfer.fromJson));
      if (list.length < page) break;
    }
    return out;
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

}

final transfersRepositoryProvider = Provider<TransfersRepository>((ref) {
  return TransfersRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
