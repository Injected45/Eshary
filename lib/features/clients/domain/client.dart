class Client {
  const Client({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.company,
    required this.code,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? company;
  final String? code;
  final DateTime createdAt;

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        company: json['company'] as String?,
        code: json['code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
