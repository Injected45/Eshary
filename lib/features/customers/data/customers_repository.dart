import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/customer_account.dart';

/// The customers' dinar accounts (migration 0091). The administrator only:
/// the database refuses an employee.
class CustomersRepository {
  CustomersRepository(this._client);
  final SupabaseClient _client;

  Future<List<CustomerBalance>> balances() async {
    final res = await _client.rpc<List<dynamic>>('customer_balances');
    return res
        .cast<Map<String, dynamic>>()
        .map(CustomerBalance.fromJson)
        .toList();
  }

  /// [book] 'cash' / 'bank' (0093); null: both.
  Future<CustomerStatement> statement(
    String clientId,
    DateTime from,
    DateTime to, {
    String? book,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'customer_statement',
      params: {
        'p_client_id': clientId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
        if (book != null) 'p_book': book,
      },
    );
    return CustomerStatement.fromJson(res);
  }

  /// [limit] null: no credit for him.
  Future<void> setLimit(String clientId, double? limit) async {
    await _client.rpc<dynamic>(
      'set_customer_credit_limit',
      params: {'p_client_id': clientId, 'p_limit': limit},
    );
  }

  /// [kind] 'collect' (he pays us), 'pay' (we pay him) with a [pocket], or
  /// 'opening' with a signed [amount] (+ he owes us). Returns his balance.
  Future<double> addEntry({
    required String clientId,
    required String kind,
    required double amount,
    String? pocket,
    String? note,
    String? requestId,
    String? book,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'customer_add_entry',
      params: {
        'p_client_id': clientId,
        'p_kind': kind,
        'p_amount': amount,
        'p_pocket': pocket,
        'p_note': note,
        'p_request_id': requestId,
        // the book (0093): a collection or payment goes through its pocket
        if (book != null) 'p_book': book,
      },
    );
    return (res['balance'] as num).toDouble();
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(ref.watch(supabaseClientProvider));
});
