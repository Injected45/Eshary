import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exchange_rates_repository.dart';
import '../domain/exchange_rates.dart';

/// Re-read after every saved operation (the last rate may have changed).
final exchangeRatesProvider = FutureProvider.autoDispose<ExchangeRates>((ref) {
  return ref.watch(exchangeRatesRepositoryProvider).current();
});

/// How far a typed rate may differ from the last one before the app asks
/// "are you sure?" (catches 72.5 for 7.25).
const double kRateWarnShare = 0.15;

/// True when [rate] is more than [kRateWarnShare] away from [last].
bool rateLooksWrong(double rate, double? last) {
  if (last == null || last <= 0) return false;
  return (rate - last).abs() / last > kRateWarnShare;
}
