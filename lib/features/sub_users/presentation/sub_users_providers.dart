import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sub_users_repository.dart';
import '../domain/sub_user.dart';

final subUsersListProvider = FutureProvider<List<SubUser>>((ref) async {
  return ref.watch(subUsersRepositoryProvider).list();
});
