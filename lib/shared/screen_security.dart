import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cache.dart';

const _key = 'security:secure-screen';
const _channel = MethodChannel('eshary/device');

/// "منع لقطات الشاشة": when on, Android blocks screenshots and screen
/// recording of the app and hides its content in the recent-apps list (the
/// window is marked FLAG_SECURE). Off by default, because people do take
/// screenshots of the app to report a problem or to show a colleague; a
/// finance app on a shared phone should turn it on.
class SecureScreenNotifier extends StateNotifier<bool> {
  SecureScreenNotifier(this._cache) : super(_cache.readString(_key) == '1');

  final JsonCache _cache;

  Future<void> set(bool on) async {
    state = on;
    await _cache.writeString(_key, on ? '1' : '');
    await applySecureScreen(on);
  }
}

final secureScreenProvider =
    StateNotifierProvider<SecureScreenNotifier, bool>((ref) {
  return SecureScreenNotifier(ref.watch(jsonCacheProvider));
});

/// Tells Android to mark (or unmark) the window. A no-op where there is no
/// native side (tests, other platforms).
Future<void> applySecureScreen(bool on) async {
  try {
    await _channel.invokeMethod<void>('setSecure', on);
  } on MissingPluginException {
    // not Android
  } on PlatformException {
    // keep going: the screen is simply not marked
  }
}
