import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../domain/app_notification.dart';

class NotificationsRepository {
  NotificationsRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  String _cacheKey() {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    return 'cache:notifications:$uid:active';
  }

  Future<AppNotification?> latestActive() async {
    final key = _cacheKey();
    try {
      final rows = await _client
          .from('notifications')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      await _cache.writeList(key, list);
      if (list.isEmpty) return null;
      return AppNotification.fromJson(list.first);
    } catch (_) {
      final cached = _cache.readList(key);
      if (cached == null || cached.isEmpty) return null;
      return AppNotification.fromJson(cached.first);
    }
  }
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
