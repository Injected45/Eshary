import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/exchange_rates.dart';

class ExchangeRatesRepository {
  ExchangeRatesRepository(this._client);
  final SupabaseClient _client;

  /// Live only: an operation cannot be saved offline either.
  Future<ExchangeRates> current() async {
    final res = await _client.rpc<dynamic>('current_exchange_rates');
    return ExchangeRates.fromJson(res as Map<String, dynamic>);
  }
}

final exchangeRatesRepositoryProvider =
    Provider<ExchangeRatesRepository>((ref) {
  return ExchangeRatesRepository(ref.watch(supabaseClientProvider));
});
