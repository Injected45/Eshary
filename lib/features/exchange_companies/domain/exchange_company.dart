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

/// What is recorded under one company's name (migration 0076): its accounts, its
/// saved parties and the financial operations recorded on it. A company is
/// deletable only when all three are zero: a name that was registered and never
/// used. Anything else, the app does not even show the delete button.
class ExchangeCompanyUsage {
  const ExchangeCompanyUsage({
    required this.accounts,
    required this.parties,
    required this.operations,
  });

  final int accounts;
  final int parties;
  final int operations;

  bool get unused => accounts == 0 && parties == 0 && operations == 0;

  factory ExchangeCompanyUsage.fromJson(Map<String, dynamic> j) =>
      ExchangeCompanyUsage(
        accounts: (j['accounts'] as num?)?.toInt() ?? 0,
        parties: (j['parties'] as num?)?.toInt() ?? 0,
        operations: (j['operations'] as num?)?.toInt() ?? 0,
      );
}
