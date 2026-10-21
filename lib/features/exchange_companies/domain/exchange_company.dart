const String kExchangeCompanyMine = 'mine';
const String kExchangeCompanyClient = 'client';

class ExchangeCompany {
  const ExchangeCompany({
    required this.id,
    required this.ownerId,
    required this.name,
    this.country,
    required this.createdAt,
    this.kind = kExchangeCompanyMine,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? country;
  final DateTime createdAt;

  /// [kExchangeCompanyMine]: a company where I hold accounts (offered as MY
  /// company in the exit / entry forms). [kExchangeCompanyClient]: the company
  /// of one of my customers (the sender's / beneficiary's), never offered as
  /// mine. Migration 0074.
  final String kind;

  bool get isMine => kind != kExchangeCompanyClient;
  bool get isClient => kind == kExchangeCompanyClient;

  factory ExchangeCompany.fromJson(Map<String, dynamic> json) =>
      ExchangeCompany(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        country: json['country'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        kind: (json['kind'] as String?) == kExchangeCompanyClient
            ? kExchangeCompanyClient
            : kExchangeCompanyMine,
      );
}
