import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/clients_repository.dart';
import '../domain/client.dart';

final clientsListProvider = FutureProvider<List<Client>>((ref) async {
  return ref.watch(clientsRepositoryProvider).list();
});
