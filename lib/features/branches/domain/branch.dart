class Branch {
  const Branch({
    required this.id,
    required this.parentAdminId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String parentAdminId;
  final String name;
  final DateTime createdAt;

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String,
        parentAdminId: json['parent_admin_id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
