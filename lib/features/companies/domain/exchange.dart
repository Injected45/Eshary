class Exchange {
  const Exchange({
    required this.id,
    required this.companyId,
    required this.name,
    required this.balance,
    required this.ourCode,
    required this.country,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String name;
  final double balance;
  final String? ourCode;
  final String? country;
  final DateTime createdAt;

  factory Exchange.fromJson(Map<String, dynamic> json) => Exchange(
        id: json['id'] as String,
        companyId: json['company_id'] as String,
        name: json['name'] as String,
        balance: (json['balance'] as num).toDouble(),
        ourCode: json['our_code'] as String?,
        country: json['country'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Exchange && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
