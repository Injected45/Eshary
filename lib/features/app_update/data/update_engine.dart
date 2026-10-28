import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Everything the update needs from the phone: where to keep the file, which
/// processors it has, downloading, checking and handing the file to Android's
/// installer. An interface so the screens and the logic are tested without a
/// phone.
abstract class UpdateEngine {
  /// The app's own folder for downloaded updates.
  Future<String> updatesDir();

  /// The processor types of this phone, best first (`arm64-v8a`, ...).
  Future<List<String>> abis();

  /// Android 8+: whether this app is allowed to install apps.
  Future<bool> canInstall();

  /// Opens the system page where the person allows it.
  Future<void> openInstallSettings();

  /// Starts Android's installer on [path] (a file in [updatesDir]).
  Future<void> install(String path);

  /// Downloads [url] to [dest]; [onProgress] gets (received, total) bytes
  /// (total is 0 when the server does not say).
  Future<void> download(
    String url,
    String dest,
    void Function(int received, int total) onProgress,
  );

  /// Whether the file exists with exactly this SHA-256 (and size, when known).
  Future<bool> fileMatches(String path, String sha256Hex, int size);

  /// Deletes every downloaded update (after the app is up to date).
  Future<void> cleanup();
}

/// The real thing, on Android (the channel is in MainActivity.kt).
class PlatformUpdateEngine implements UpdateEngine {
  /// [allowLoopbackHttp] is for tests only (a local server on this computer);
  /// the app always uses the default: https only.
  PlatformUpdateEngine({this.allowLoopbackHttp = false});

  final bool allowLoopbackHttp;

  static const _channel = MethodChannel('eshary/update');

  @override
  Future<String> updatesDir() async =>
      (await _channel.invokeMethod<String>('updatesDir'))!;

  @override
  Future<List<String>> abis() async {
    final list = await _channel.invokeMethod<List<Object?>>('abis');
    return [for (final a in list ?? const []) a.toString()];
  }

  @override
  Future<bool> canInstall() async =>
      (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', path);

  @override
  Future<void> download(
    String url,
    String dest,
    void Function(int received, int total) onProgress,
  ) async {
    final uri = Uri.parse(url);
    // only the project's own secure address (the file is also checked against
    // its SHA-256 and Android checks the signature, but never fetch over HTTP)
    final loopback = allowLoopbackHttp &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost');
    if (uri.scheme != 'https' && !loopback) {
      throw const FormatException('update url must be https');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 15);
    final part = File('$dest.part');
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw HttpException('download failed (${res.statusCode})', uri: uri);
      }
      final total = res.contentLength > 0 ? res.contentLength : 0;
      var received = 0;
      final sink = part.openWrite();
      try {
        // a stalled connection ends the download instead of hanging forever
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      final target = File(dest);
      if (await target.exists()) await target.delete();
      await part.rename(dest);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> fileMatches(String path, String sha256Hex, int size) =>
      fileHasSha256(path, sha256Hex, size);

  @override
  Future<void> cleanup() async {
    try {
      final dir = Directory(await updatesDir());
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {
      // leftovers are harmless
    }
  }
}

/// True when [path] is a file whose SHA-256 is [sha256Hex] (and whose length is
/// [size], when [size] > 0). Streams the file: it is never loaded whole.
Future<bool> fileHasSha256(String path, String sha256Hex, int size) async {
  final file = File(path);
  if (!await file.exists()) return false;
  if (size > 0 && await file.length() != size) return false;
  final out = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(out);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return out.events.single.toString() == sha256Hex.toLowerCase();
}
