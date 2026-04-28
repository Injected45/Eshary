import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny disk cache for read-only collection JSON. Used by repositories so
/// that recent lists are still browsable when the network is down.
/// Writes always go through the live Supabase client; this cache only
/// covers reads, scoped per signed-in user via the cache key.
class JsonCache {
  JsonCache(this._prefs);
  final SharedPreferences _prefs;

  String? readString(String key) => _prefs.getString(key);

  Future<void> writeString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  List<Map<String, dynamic>>? readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> rows) async {
    await _prefs.setString(key, jsonEncode(rows));
  }

  Future<void> clear() => _prefs.clear();
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override with the loaded SharedPreferences');
});

final jsonCacheProvider = Provider<JsonCache>((ref) {
  return JsonCache(ref.watch(sharedPreferencesProvider));
});
