class ExchangeCompany {
  const ExchangeCompany({
    required this.id,
    required this.ownerId,
    required this.name,
    this.country,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? country;
  final DateTime createdAt;

  factory ExchangeCompany.fromJson(Map<String, dynamic> json) =>
      ExchangeCompany(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        country: json['country'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
