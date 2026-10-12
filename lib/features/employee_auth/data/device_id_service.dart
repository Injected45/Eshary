import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/cache.dart';

/// The key that binds an employee to ONE phone.
///
/// The key is "NEW" or "NEW~OLD":
///   * NEW  a hash of this phone's own Android ID (never the raw ID), made in
///          the native side. Two identical phones have different keys. When the
///          native value is unavailable (other platforms, a failure) a random
///          id made once and kept on the phone is used instead.
///   * OLD  the key the previous versions of the app used (the Android build id,
///          the same on every phone of one model). It is offered only so that
///          an employee bound under the old key is moved to the new one at the
///          next sign-in without an administrator resetting anything; the server
///          accepts it for that one move (migration 0065).
class DeviceIdService {
  DeviceIdService(this._prefs, {Future<String?> Function()? nativeKey})
      : _nativeKey = nativeKey ?? _androidKey;

  final SharedPreferences _prefs;
  final Future<String?> Function() _nativeKey;

  /// What versions before this one cached.
  static const _kLegacyKey = 'eshary.device_id.v1';

  /// The new key, cached so it is the same at every sign-in.
  static const _kNewKey = 'eshary.device_id.v2';

  static const _channel = MethodChannel('eshary/device');

  static Future<String?> _androidKey() async {
    if (!Platform.isAndroid) return null;
    try {
      final k = await _channel.invokeMethod<String>('deviceKey');
      return (k == null || k.isEmpty) ? null : k;
    } catch (_) {
      return null;
    }
  }

  Future<String> get() async {
    var fresh = _prefs.getString(_kNewKey);
    if (fresh == null || fresh.isEmpty) {
      fresh = await _nativeKey() ??
          await _resolveOtherPlatforms() ??
          _generateFallback();
      await _prefs.setString(_kNewKey, fresh);
    }
    final old = await _legacy();
    return (old != null && old.isNotEmpty && old != fresh)
        ? '$fresh~$old'
        : fresh;
  }

  /// The key an older version stored (or would have computed on this phone).
  Future<String?> _legacy() async {
    final cached = _prefs.getString(_kLegacyKey);
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      if (Platform.isAndroid) {
        final id = (await DeviceInfoPlugin().androidInfo).id;
        return id.isNotEmpty ? id : null;
      }
    } catch (_) {
      // no old key to offer
    }
    return null;
  }

  Future<String?> _resolveOtherPlatforms() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        return (await info.iosInfo).identifierForVendor;
      }
      if (Platform.isWindows) {
        return (await info.windowsInfo).deviceId;
      }
      if (Platform.isMacOS) {
        return (await info.macOsInfo).systemGUID;
      }
      if (Platform.isLinux) {
        return (await info.linuxInfo).machineId;
      }
    } catch (_) {
      // fall through to the random id
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
