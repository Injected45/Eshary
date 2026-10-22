import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';

final latestNotificationProvider =
    FutureProvider<AppNotification?>((ref) async {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.latestActive();
});

/// Everything the platform published that is still on, newest first. Re-read
/// every few seconds by the realtime sync (realtime_sync.dart), which is how a
/// new notification reaches the open app.
final notificationsListProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  return ref.watch(notificationsRepositoryProvider).listActive();
});

/// When this person last opened the notifications (kept on the phone, per
/// account). Anything newer is "unread".
class NotificationsSeen extends StateNotifier<DateTime?> {
  NotificationsSeen(this._ref, this._uid) : super(_read(_ref, _uid));

  final Ref _ref;
  final String? _uid;

  static String _key(String? uid) => 'notif_seen:${uid ?? 'anon'}';

  static DateTime? _read(Ref ref, String? uid) {
    final raw = ref.read(jsonCacheProvider).readString(_key(uid));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Marks everything shown so far as read.
  Future<void> markSeen(Iterable<AppNotification> shown) async {
    if (shown.isEmpty) return;
    final newest =
        shown.map((n) => n.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    if (state != null && !newest.isAfter(state!)) return;
    state = newest;
    await _ref
        .read(jsonCacheProvider)
        .writeString(_key(_uid), newest.toUtc().toIso8601String());
  }
}

final notificationsSeenProvider =
    StateNotifierProvider<NotificationsSeen, DateTime?>((ref) {
  return NotificationsSeen(ref, ref.watch(currentUserIdProvider));
});

/// How many notifications arrived after the last time they were opened.
final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsListProvider).valueOrNull;
  if (list == null) return 0;
  final seen = ref.watch(notificationsSeenProvider);
  if (seen == null) return list.length;
  return list.where((n) => n.createdAt.isAfter(seen)).length;
});
