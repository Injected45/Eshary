import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';

final latestNotificationProvider =
    FutureProvider<AppNotification?>((ref) async {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.latestActive();
});
