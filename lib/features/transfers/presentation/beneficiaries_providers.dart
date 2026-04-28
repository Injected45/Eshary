import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/beneficiaries_repository.dart';
import '../domain/beneficiary.dart';

final beneficiariesListProvider =
    FutureProvider<List<Beneficiary>>((ref) async {
  return ref.watch(beneficiariesRepositoryProvider).list();
});
