import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/ledger.dart';

/// The general ledger (migration 0092). The administrator only.
class LedgerRepository {
  LedgerRepository(this._client);
  final SupabaseClient _client;

  String _t(DateTime d) => d.toUtc().toIso8601String();

  /// One book ('cash' / 'bank') or both (null) converting bank dinars into
  /// cash ones at [factor] (0093). Sent only when set, so a database before
  /// 0093 still answers.
  Map<String, dynamic> _scope(String? book, double factor) => {
        if (book != null) 'p_book': book,
        if (book == null && factor != 1) 'p_bank_factor': factor,
      };

  Future<List<TrialLine>> trialBalance(
    DateTime to, {
    String? book,
    double factor = 1,
  }) async {
    final res = await _client.rpc<List<dynamic>>(
      'ledger_trial_balance',
      params: {'p_to': _t(to), ..._scope(book, factor)},
    );
    return res.cast<Map<String, dynamic>>().map(TrialLine.fromJson).toList();
  }

  Future<IncomeStatement> incomeStatement(
    DateTime from,
    DateTime to, {
    String? book,
    double factor = 1,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'ledger_income_statement',
      params: {'p_from': _t(from), 'p_to': _t(to), ..._scope(book, factor)},
    );
    return IncomeStatement.fromJson(res);
  }

  Future<BalanceSheet> balanceSheet(
    DateTime at, {
    String? book,
    double factor = 1,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'ledger_balance_sheet',
      params: {'p_at': _t(at), ..._scope(book, factor)},
    );
    return BalanceSheet.fromJson(res);
  }

  Future<Journal> journal(DateTime from, DateTime to, {String? book}) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'ledger_journal',
      params: {
        'p_from': _t(from),
        'p_to': _t(to),
        if (book != null) 'p_book': book,
      },
    );
    return Journal.fromJson(res);
  }

  Future<List<PeriodClose>> closes() async {
    final res = await _client.rpc<List<dynamic>>('ledger_closes');
    return res.cast<Map<String, dynamic>>().map(PeriodClose.fromJson).toList();
  }

  /// Seals the books up to [end]; returns the net profit since the last close.
  Future<double> closePeriod(DateTime end, {String? note}) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'close_period',
      params: {'p_end': _t(end), 'p_note': note},
    );
    return (res['net_profit'] as num? ?? 0).toDouble();
  }

  Future<Reconciliation> reconcile({
    required String exchangeId,
    required DateTime at,
    required double theirBalance,
    String? note,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'reconcile_account',
      params: {
        'p_exchange_id': exchangeId,
        'p_at': _t(at),
        'p_their_balance': theirBalance,
        'p_note': note,
      },
    );
    return Reconciliation(
      at: at,
      theirBalance: (res['their_balance'] as num).toDouble(),
      ourBalance: (res['our_balance'] as num).toDouble(),
      difference: (res['difference'] as num).toDouble(),
      note: note,
    );
  }

  Future<List<Reconciliation>> reconciliations(String exchangeId) async {
    final res = await _client.rpc<List<dynamic>>(
      'account_reconciliations_list',
      params: {'p_exchange_id': exchangeId},
    );
    return res
        .cast<Map<String, dynamic>>()
        .map(Reconciliation.fromJson)
        .toList();
  }
}

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(ref.watch(supabaseClientProvider));
});
