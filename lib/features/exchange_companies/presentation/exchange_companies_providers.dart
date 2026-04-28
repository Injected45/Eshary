import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exchange_companies_repository.dart';
import '../domain/exchange_company.dart';

final exchangeCompaniesListProvider =
    FutureProvider<List<ExchangeCompany>>((ref) async {
  return ref.watch(exchangeCompaniesRepositoryProvider).list();
});
