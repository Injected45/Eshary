class AppNotification {
  const AppNotification({
    required this.id,
    this.title,
    required this.body,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String? title;
  final String body;
  final bool isActive;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String?,
        body: json['body'] as String,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };
}
