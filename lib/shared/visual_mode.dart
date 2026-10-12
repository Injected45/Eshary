import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cache.dart';

/// Two shades of dark, chosen from Settings. The visual language of the app
/// (glass, animated background, accents) is the same in both; only the deep
/// base colour behind everything changes.
///   * [deep] — the original OLED-friendly black (0xFF020617).
///   * [calm] — a noticeably softer navy that is easier on the eye in
///     daylight (0xFF1E293B).
/// A true light mode is intentionally not offered: the whole UI (glass bars,
/// radial blobs, borders) is tuned for a dark base.
enum AppVisualMode { deep, calm }

const _visualModeKey = 'theme:visual-mode';

class VisualModeNotifier extends StateNotifier<AppVisualMode> {
  VisualModeNotifier(this._cache)
      : super(_decode(_cache.readString(_visualModeKey)));

  final JsonCache _cache;

  static AppVisualMode _decode(String? s) =>
      s == 'calm' ? AppVisualMode.calm : AppVisualMode.deep;

  Future<void> set(AppVisualMode mode) async {
    if (mode == state) return;
    state = mode;
    await _cache.writeString(
      _visualModeKey,
      mode == AppVisualMode.calm ? 'calm' : 'deep',
    );
  }
}

final visualModeProvider =
    StateNotifierProvider<VisualModeNotifier, AppVisualMode>(
  (ref) => VisualModeNotifier(ref.watch(jsonCacheProvider)),
);
