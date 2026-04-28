class Company {
  const Company({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.startRef,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String startRef;
  final DateTime createdAt;

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        startRef: json['start_ref'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'owner_id': ownerId,
        'name': name,
        'start_ref': startRef,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Company && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
