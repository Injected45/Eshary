import 'package:audioplayers/audioplayers.dart';

final _player = AudioPlayer();

/// Plays a short ding from `assets/sounds/alert.mp3`. Fire-and-forget — any
/// playback error is swallowed so it never breaks the calling flow.
Future<void> playAlert() async {
  try {
    await _player.stop();
    await _player.play(AssetSource('sounds/alert.mp3'));
  } catch (_) {
    // ignore — audio is non-critical feedback
  }
}
