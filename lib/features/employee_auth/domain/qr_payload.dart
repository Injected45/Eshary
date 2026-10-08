/// The text encoded in the employee sign-in QR.
///
/// The prefix is mandatory: without it any QR in the world (a receipt, a wifi
/// card) would be treated as a sign-in token and burn a call to the backend.
/// The QR carries exactly the one-time token the backend issued — nothing else
/// (no user id, role or URL parameters); expiry, single use and e-mail / device
/// checks are enforced by the server only.
const String _prefix = 'eshary://employee?t=';

final RegExp _tokenShape = RegExp(r'^[0-9a-f]{64}$');

String employeeQrPayload(String token) => '$_prefix${token.trim()}';

/// Returns the token inside a scanned [raw] value, or null when it is not one
/// of our QRs (wrong prefix, or not a 64-char hex token).
String? employeeTokenFromQrPayload(String raw) {
  final text = raw.trim();
  if (!text.startsWith(_prefix)) return null;
  final token = text.substring(_prefix.length).trim();
  return _tokenShape.hasMatch(token) ? token : null;
}
