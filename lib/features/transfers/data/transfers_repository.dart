import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../../../shared/libya_time.dart';
import '../domain/transfer.dart';

class TransfersRepository {
  TransfersRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  String _cacheKey(TransferStatus status, String? createdByEmployeeId) {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    final suffix =
        createdByEmployeeId == null ? '' : ':emp:$createdByEmployeeId';
    return 'cache:transfers:$uid:${transferStatusToDb(status)}$suffix';
  }

  /// When [createdByEmployeeId] is non-null the result is scoped to rows
  /// the given sub_user authored — used by the employee app so each
  /// employee only sees their own daily / archived operations even though
  /// RLS would otherwise expose every sibling employee's record.
  /// Whether any exit was ever posted: one row, not the whole history.
  Future<bool> hasArchived() async {
    final rows = await _client
        .from('transfers')
        .select('id')
        .eq('status', transferStatusToDb(TransferStatus.archived))
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<List<Transfer>> listByStatus(
    TransferStatus status, {
    String? createdByEmployeeId,
  }) async {
    final key = _cacheKey(status, createdByEmployeeId);
    try {
      // Page by page: one request returns at most 1000 rows, and the archive
      // and every period report built on it must never be cut short silently.
      const page = 1000;
      final list = <Map<String, dynamic>>[];
      for (var from = 0;; from += page) {
        var filter = _client
            .from('transfers')
            .select()
            .eq('status', transferStatusToDb(status));
        if (createdByEmployeeId != null) {
          filter = filter.eq('created_by_employee_id', createdByEmployeeId);
        }
        final rows = await filter
            .order('created_at', ascending: false)
            .order('id')
            .range(from, from + page - 1);
        final chunk = (rows as List).cast<Map<String, dynamic>>();
        list.addAll(chunk);
        if (chunk.length < page) break;
      }
      await _cache.writeList(key, list);
      return list.map(Transfer.fromJson).toList();
    } catch (e) {
      final cached = _cache.readList(key);
      if (cached == null) rethrow;
      return cached.map(Transfer.fromJson).toList();
    }
  }

  /// Today's executed exits (posted at save). "Today" is the Libya day, so the
  /// list empties by itself when a new day begins, on every phone at once.
  Future<List<Transfer>> listToday({String? createdByEmployeeId}) async {
    final start = libyaDayStart(libyaToday());
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
    required double rate,
    String? lydMethod = 'cash',
    String? requestId,
    String? customerId,
    double? lydPaid,
    bool overLimit = false,
    String? book,
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
        // shown on the screen before saving; since 0087 the database gives
        // the number at save time (under a lock), so read it from the result
        'p_reference': reference,
        // the database computes the dinars and may use the administrator's
        // last rate instead (an employee without "rate_edit"), migration 0081
        'p_rate': rate,
        // how the dinars came in: the box or the bank (migration 0086)
        'p_lyd_method': lydMethod,
        // the same request sent again returns the saved exit (0087)
        'p_request_id': requestId,
        // on credit (0091): who pays the dinars and how much was paid now
        // (null = all of them); the administrator may go over the limit
        'p_customer_id': customerId,
        'p_lyd_paid': lydPaid,
        'p_over_limit': overLimit,
        // its book: cash dinars or bank dinars (0093)
        'p_book': book,
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
