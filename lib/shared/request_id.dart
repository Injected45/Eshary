import 'dart:math';

final Random _random = Random.secure();

/// A random UUID (version 4) naming one save request. The database keeps it
/// with the operation (migration 0087): sending the same request again — the
/// network dropped after the server saved it — returns that operation instead
/// of saving it, and moving the balance, a second time.
String newRequestId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
