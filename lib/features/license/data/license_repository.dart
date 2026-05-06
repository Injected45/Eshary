import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/cache.dart';
import '../domain/license_status.dart';

class LicenseRepository {
  LicenseRepository(this._client, this._cache);
  final SupabaseClient _client;
  final JsonCache _cache;

  String _cacheKey() {
    final uid = _client.auth.currentUser?.id ?? 'anon';
    return 'cache:license:$uid';
  }

  /// Calls the `current_license_status()` RPC. Caches the row on success and
  /// serves the cache on transient errors so the gate keeps working offline.
  /// If neither the network nor the cache yields a row, returns
  /// [LicenseStatus.missing] (treated as pending) — the user stays gated.
  ///
  /// Negative states ('blocked', 'expired', 'pending') are NEVER served from
  /// cache: those decisions must come from the live server, otherwise a
  /// stale cached 'blocked' could auto-sign-out a user who has since been
  /// re-activated.
  Future<LicenseStatus> fetch() async {
    final key = _cacheKey();
    try {
      final res = await _client.rpc<List<dynamic>>('current_license_status');
      final list = res.cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        return LicenseStatus.missing;
      }
      final row = list.first;
      final parsed = LicenseStatus.fromJson(row);
      // Only cache "user can use the app" states. Caching 'blocked' /
      // 'expired' / 'pending' would let stale data re-trigger the
      // force-logout listener after the server has already cleared it.
      if (parsed.isValid) {
        await _cache.writeString(key, jsonEncode(row));
      } else {
        await _cache.writeString(key, '');
      }
      return parsed;
    } catch (_) {
      final cached = _cache.readString(key);
      if (cached == null || cached.isEmpty) return LicenseStatus.missing;
      final row = jsonDecode(cached) as Map<String, dynamic>;
      final parsed = LicenseStatus.fromJson(row);
      // Belt-and-suspenders: if cached data is somehow non-valid, fall
      // through to missing rather than honouring it.
      if (!parsed.isValid) return LicenseStatus.missing;
      return parsed;
    }
  }

  /// Clear the cached license row for the current user. Called on sign-out
  /// so a subsequent sign-in (possibly as a different user on the same
  /// device) cannot inherit stale state.
  Future<void> clearCache() async {
    await _cache.writeString(_cacheKey(), '');
  }
}

final licenseRepositoryProvider = Provider<LicenseRepository>((ref) {
  return LicenseRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(jsonCacheProvider),
  );
});
