import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/cache.dart';

/// Stable per-install device identifier used to bind a sub_user to a single
/// device on first login (Phase 2 of the Employee Management module).
///
/// Strategy:
///   1. Try the OS-provided identifier (Android `id`, iOS `identifierForVendor`,
///      Windows `deviceId`, etc.) — survives app reinstalls on most platforms.
///   2. Fall back to a one-time generated UUID stored in SharedPreferences
///      so platforms without a usable system ID still get a stable value.
///   3. Cache the resolved ID in SharedPreferences under [_kCacheKey] so the
///      first login and subsequent logins always present the same value.
class DeviceIdService {
  DeviceIdService(this._prefs);

  final SharedPreferences _prefs;
  static const _kCacheKey = 'eshary.device_id.v1';

  Future<String> get() async {
    final cached = _prefs.getString(_kCacheKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final resolved = await _resolveFromPlatform();
    final id = (resolved != null && resolved.isNotEmpty)
        ? resolved
        : _generateFallback();
    await _prefs.setString(_kCacheKey, id);
    return id;
  }

  Future<String?> _resolveFromPlatform() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return a.id.isNotEmpty ? a.id : null;
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return i.identifierForVendor;
      }
      if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return w.deviceId;
      }
      if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        return m.systemGUID;
      }
      if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return l.machineId;
      }
    } catch (_) {
      // Fall through to UUID fallback.
    }
    return null;
  }

  String _generateFallback() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${bytes.sublist(0, 4).map(hex).join()}'
        '-${bytes.sublist(4, 6).map(hex).join()}'
        '-${bytes.sublist(6, 8).map(hex).join()}'
        '-${bytes.sublist(8, 10).map(hex).join()}'
        '-${bytes.sublist(10, 16).map(hex).join()}';
  }
}

final deviceIdServiceProvider = Provider<DeviceIdService>((ref) {
  return DeviceIdService(ref.watch(sharedPreferencesProvider));
});
