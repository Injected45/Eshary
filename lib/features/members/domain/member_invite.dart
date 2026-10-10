/// What the account gets when the invited person comes in.
enum InviteLicense {
  /// A 3-day trial, active at once.
  trial,

  /// A permanent licence, active at once.
  lifetime,

  /// Created but waiting for the administrator to activate it.
  pending;

  String get db => name;

  String get label => switch (this) {
        InviteLicense.trial => 'تجريبي 3 أيام',
        InviteLicense.lifetime => 'دائم',
        InviteLicense.pending => 'بانتظار تفعيلي',
      };

  static InviteLicense parse(String s) => InviteLicense.values.firstWhere(
        (l) => l.name == s,
        orElse: () => InviteLicense.pending,
      );
}

/// pending / used / revoked / expired.
enum InviteStatus {
  pending,
  used,
  revoked,
  expired;

  String get label => switch (this) {
        InviteStatus.pending => 'بانتظار الدخول',
        InviteStatus.used => 'تم الدخول',
        InviteStatus.revoked => 'مُلغاة',
        InviteStatus.expired => 'منتهية',
      };

  static InviteStatus parse(String s) => InviteStatus.values.firstWhere(
        (l) => l.name == s,
        orElse: () => InviteStatus.expired,
      );
}

/// One row of the administrator's invitations list. The secret is never part
/// of it: the server keeps only its hash and shows the secret once, at
/// creation ([CreatedInvite]).
class MemberInvite {
  const MemberInvite({
    required this.id,
    required this.label,
    required this.phone,
    required this.license,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.usedAt,
  });

  final String id;
  final String label;
  final String phone;
  final InviteLicense license;
  final InviteStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? usedAt;

  factory MemberInvite.fromJson(Map<String, dynamic> j) => MemberInvite(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        license: InviteLicense.parse(j['license'] as String),
        status: InviteStatus.parse(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
        usedAt: j['used_at'] == null
            ? null
            : DateTime.parse(j['used_at'] as String).toLocal(),
      );
}

/// A freshly created invitation: the only moment the secret exists in the app.
class CreatedInvite {
  const CreatedInvite({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final DateTime expiresAt;

  /// The text the QR encodes (and the text the administrator sends).
  String get payload => invitePayload(token);

  factory CreatedInvite.fromJson(Map<String, dynamic> j) => CreatedInvite(
        id: j['id'] as String,
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
      );
}

/// The prefix is mandatory: without it any QR in the world would be treated as
/// an invitation and cost a call to the server. The QR carries only the
/// one-time secret; the phone, expiry and single use are enforced by the server.
const String _invitePrefix = 'eshary://invite?t=';

final RegExp _tokenShape = RegExp(r'^[0-9a-f]{64}$');

String invitePayload(String token) => '$_invitePrefix${token.trim()}';

/// The secret inside a scanned or pasted [raw] text, or null when it is not an
/// invitation. Accepts the full payload (QR / link) or the bare 64-hex secret,
/// anywhere inside a longer message (e.g. the whole WhatsApp text).
String? inviteTokenFromText(String raw) {
  final text = raw.trim();
  final at = text.indexOf(_invitePrefix);
  if (at >= 0) {
    final rest = text.substring(at + _invitePrefix.length);
    final m = RegExp(r'^[0-9a-f]{64}').firstMatch(rest);
    return m?.group(0);
  }
  return _tokenShape.hasMatch(text) ? text : null;
}
