import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/branches_repository.dart';
import '../domain/branch.dart';

final branchesListProvider = FutureProvider<List<Branch>>((ref) async {
  return ref.watch(branchesRepositoryProvider).list();
});
