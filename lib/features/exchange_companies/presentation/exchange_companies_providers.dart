import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exchange_companies_repository.dart';
import '../domain/exchange_company.dart';

final exchangeCompaniesListProvider =
    FutureProvider<List<ExchangeCompany>>((ref) async {
  return ref.watch(exchangeCompaniesRepositoryProvider).list();
});

/// The exchange companies where I hold accounts: what the exit / entry forms,
/// "حساباتي" and the new-account dialog offer.
final myExchangeCompaniesProvider =
    Provider<AsyncValue<List<ExchangeCompany>>>((ref) {
  return ref.watch(exchangeCompaniesListProvider).whenData((all) => [
        for (final c in all)
          if (c.isMine) c
      ]);
});

/// The companies of my customers: what the customer dialog offers. Never
/// shown as my own company.
final clientCompaniesProvider =
    Provider<AsyncValue<List<ExchangeCompany>>>((ref) {
  return ref.watch(exchangeCompaniesListProvider).whenData((all) => [
        for (final c in all)
          if (c.isClient) c
      ]);
});
