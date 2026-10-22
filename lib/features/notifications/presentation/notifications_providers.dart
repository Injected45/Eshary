import 'dart:convert';

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

/// The notifications this person has opened (kept on the phone, per account).
/// Opening one reads it; the bell counts only the ones not opened yet.
class NotificationsRead extends StateNotifier<Set<String>> {
  NotificationsRead(this._ref, this._uid) : super(_load(_ref, _uid));

  final Ref _ref;
  final String? _uid;

  static const _keep = 300;

  static String _key(String? uid) => 'notif_read:${uid ?? 'anon'}';

  static Set<String> _load(Ref ref, String? uid) {
    final raw = ref.read(jsonCacheProvider).readString(_key(uid));
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Marks one notification as opened.
  Future<void> markRead(String id) async {
    if (state.contains(id)) return;
    final next = {...state, id};
    // an old id no one lists any more is not worth keeping forever
    final kept = next.length > _keep
        ? next.toList().sublist(next.length - _keep).toSet()
        : next;
    state = kept;
    await _ref
        .read(jsonCacheProvider)
        .writeString(_key(_uid), jsonEncode(kept.toList()));
  }
}

final notificationsReadProvider =
    StateNotifierProvider<NotificationsRead, Set<String>>((ref) {
  return NotificationsRead(ref, ref.watch(currentUserIdProvider));
});

/// How many notifications have not been opened yet: the red number on the bell.
final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsListProvider).valueOrNull;
  if (list == null) return 0;
  final read = ref.watch(notificationsReadProvider);
  return list.where((n) => !read.contains(n.id)).length;
});
