import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/activity_log.dart';

class ActivityLogsRepository {
  ActivityLogsRepository(this._client);
  final SupabaseClient _client;

  /// Returns the most-recent activity for a single sub_user. RLS limits
  /// results to logs the caller is allowed to see (admin = own employees;
  /// employee = own logs).
  Future<List<ActivityLog>> listForSubUser(
    String subUserId, {
    int limit = 100,
  }) async {
    final rows = await _client
        .from('employee_activity_logs')
        .select()
        .eq('sub_user_id', subUserId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => ActivityLog.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final activityLogsRepositoryProvider =
    Provider<ActivityLogsRepository>((ref) {
  return ActivityLogsRepository(ref.watch(supabaseClientProvider));
});

/// Family provider keyed by sub_user_id. Watched by the activity log
/// screen — invalidate after any new employee action to refresh.
final subUserActivityLogsProvider =
    FutureProvider.family<List<ActivityLog>, String>((ref, subUserId) async {
  return ref
      .watch(activityLogsRepositoryProvider)
      .listForSubUser(subUserId);
});
