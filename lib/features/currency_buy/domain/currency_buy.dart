enum CurrencyBuyStatus { pending, daily, archived }

CurrencyBuyStatus _parseStatus(String s) {
  switch (s) {
    case 'pending':
      return CurrencyBuyStatus.pending;
    case 'archived':
      return CurrencyBuyStatus.archived;
    default:
      return CurrencyBuyStatus.daily;
  }
}

String currencyBuyStatusToDb(CurrencyBuyStatus s) {
  switch (s) {
    case CurrencyBuyStatus.pending:
      return 'pending';
    case CurrencyBuyStatus.archived:
      return 'archived';
    case CurrencyBuyStatus.daily:
      return 'daily';
  }
}

class CurrencyBuy {
  const CurrencyBuy({
    required this.id,
    required this.ownerId,
    required this.myCompanyId,
    required this.exchangeId,
    required this.clientId,
    required this.clientFromAccount,
    required this.usdAmount,
    required this.rate,
    required this.lydAmount,
    required this.reference,
    required this.status,
    required this.createdAt,
    required this.archivedAt,
  });

  final String id;
  final String ownerId;
  final String myCompanyId;
  final String exchangeId;
  final String? clientId;
  final String? clientFromAccount;
  final double usdAmount;
  final double rate;
  final double lydAmount;
  final String reference;
  final CurrencyBuyStatus status;
  final DateTime createdAt;
  final DateTime? archivedAt;

  factory CurrencyBuy.fromJson(Map<String, dynamic> json) => CurrencyBuy(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        myCompanyId: json['my_company_id'] as String,
        exchangeId: json['exchange_id'] as String,
        clientId: json['client_id'] as String?,
        clientFromAccount: json['client_from_account'] as String?,
        usdAmount: (json['usd_amount'] as num).toDouble(),
        rate: (json['rate'] as num).toDouble(),
        lydAmount: (json['lyd_amount'] as num).toDouble(),
        reference: (json['reference'] as String?) ?? '',
        status: _parseStatus(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
      );
}
