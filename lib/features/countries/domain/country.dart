class Country {
  const Country({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final DateTime createdAt;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
