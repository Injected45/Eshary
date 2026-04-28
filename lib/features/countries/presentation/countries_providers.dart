import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/countries_repository.dart';
import '../domain/country.dart';

final countriesListProvider = FutureProvider<List<Country>>((ref) async {
  return ref.watch(countriesRepositoryProvider).list();
});
