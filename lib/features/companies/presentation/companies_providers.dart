import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/companies_repository.dart';
import '../data/exchanges_repository.dart';
import '../domain/company.dart';
import '../domain/exchange.dart';

final companiesListProvider = FutureProvider<List<Company>>((ref) async {
  return ref.watch(companiesRepositoryProvider).list();
});

final allExchangesProvider = FutureProvider<List<Exchange>>((ref) async {
  return ref.watch(exchangesRepositoryProvider).listAll();
});

final exchangesByCompanyProvider =
    FutureProvider.family<List<Exchange>, String>((ref, companyId) async {
  return ref.watch(exchangesRepositoryProvider).listForCompany(companyId);
});

final nextReferenceProvider =
    FutureProvider.family<String, String>((ref, companyId) async {
  return ref.watch(companiesRepositoryProvider).nextReference(companyId);
});

final accountHasTransactionsProvider =
    FutureProvider.family<bool, String>((ref, exchangeId) async {
  return ref.watch(exchangesRepositoryProvider).hasTransactions(exchangeId);
});
