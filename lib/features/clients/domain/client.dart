class Client {
  const Client({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.company,
    required this.code,
    required this.createdAt,
    this.refPrefix,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? company;
  final String? code;
  final DateTime createdAt;

  /// The letters this sender's reference numbers always start with (TRC for
  /// TRC185, TRC250 ...). The entry form shows them fixed; only the number is
  /// typed. Null when the sender has none.
  final String? refPrefix;

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        company: json['company'] as String?,
        code: json['code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        refPrefix: json['ref_prefix'] as String?,
      );
}

/// The reference to record: the sender's fixed letters followed by the number
/// that was typed. Nothing typed gives nothing. A reference typed with the
/// letters already in front is not doubled (TRC + "trc185" is "trc185").
String fullReference(String? prefix, String typed) {
  final number = typed.trim();
  final letters = (prefix ?? '').trim();
  if (number.isEmpty) return '';
  if (letters.isEmpty) return number;
  return number.toLowerCase().startsWith(letters.toLowerCase())
      ? number
      : '$letters$number';
}

/// How a code or a company name is compared: Western digits, no spaces, lower
/// case. ٥٥٢١ and "5521 " are the same code; "بهار  روز" and "بهار روز" the
/// same company. Mirrors `_party_key` in migration 0068.
String partyKey(String? s) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in (s ?? '').runes) {
    final ch = String.fromCharCode(r);
    final i = arabicIndic.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch.trim().isNotEmpty) {
      b.write(ch.toLowerCase());
    }
  }
  return b.toString();
}

/// The code as it is stored: digits in Western form, spaces removed (letters
/// keep their case, leading zeros stay).
String cleanCode(String? s) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in (s ?? '').runes) {
    final ch = String.fromCharCode(r);
    final i = arabicIndic.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch.trim().isNotEmpty) {
      b.write(ch);
    }
  }
  return b.toString();
}

/// What a party with no name is called everywhere (lists, messages, reports):
/// its code. Most merchants are known by their code only.
String nameForCode(String code) => 'كود $code';
