import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../domain/app_release.dart';

/// Reads the latest published release (`latest_app_release()`, migration
/// 0079). Anyone may ask, signed in or not: the check also runs on the sign-in
/// screen.
class AppUpdateRepository {
  AppUpdateRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  static const _key = 'app_update:latest';

  /// The latest release, or null when none is published. Throws when the
  /// server cannot be reached. What it answered is kept, so a forced update
  /// is still enforced while the phone is offline.
  Future<AppRelease?> fetchLatest() async {
    final raw = await _client.rpc<dynamic>(
      'latest_app_release',
      params: {'p_platform': 'android'},
    ).timeout(const Duration(seconds: 10));
    if (raw == null) {
      await _cache.writeString(_key, 'null');
      return null;
    }
    final release = AppRelease.fromJson(raw as Map<String, dynamic>);
    await _cache.writeString(_key, jsonEncode(release.toJson()));
    return release;
  }

  /// What the server last answered (null: nothing known, or none published).
  AppRelease? cached() {
    final raw = _cache.readString(_key);
    if (raw == null || raw == 'null') return null;
    try {
      return AppRelease.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
