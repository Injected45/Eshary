class Beneficiary {
  const Beneficiary({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.account,
    required this.code,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? account;
  final String? code;
  final DateTime createdAt;

  factory Beneficiary.fromJson(Map<String, dynamic> json) => Beneficiary(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        account: json['account'] as String?,
        code: json['code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
