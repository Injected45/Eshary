/// One account in the treasury: its dollars and their cost price (migration
/// 0082, weighted average). [costRate] is null until the administrator set the
/// opening cost of the account (or an empty account received its first buy).
class TreasuryPosition {
  const TreasuryPosition({
    required this.exchangeId,
    required this.companyName,
    required this.accountName,
    required this.balance,
    required this.costRate,
    required this.bookValue,
    required this.costUpdatedAt,
    this.marketRate,
    this.unrealized,
  });

  final String exchangeId;
  final String companyName;
  final String accountName;
  final double balance;

  /// Dinars per dollar, kept to 6 decimals by the database.
  final double? costRate;

  /// balance × cost, in dinars, rounded by the database.
  final double? bookValue;
  final DateTime? costUpdatedAt;

  /// The administrator's last sell rate, used as the market rate (0084).
  final double? marketRate;

  /// balance × (market − cost): what the dollars held would earn (or lose,
  /// negative) if sold now. Null without a cost or a market rate.
  final double? unrealized;

  bool get hasCost => costRate != null;

  factory TreasuryPosition.fromJson(Map<String, dynamic> json) =>
      TreasuryPosition(
        exchangeId: json['exchange_id'] as String,
        companyName: (json['company_name'] as String?) ?? '',
        accountName: (json['account_name'] as String?) ?? '',
        balance: (json['balance'] as num).toDouble(),
        costRate: (json['cost_rate'] as num?)?.toDouble(),
        bookValue: (json['book_value'] as num?)?.toDouble(),
        costUpdatedAt: json['cost_updated_at'] == null
            ? null
            : DateTime.parse(json['cost_updated_at'] as String),
        marketRate: (json['market_rate'] as num?)?.toDouble(),
        unrealized: (json['unrealized'] as num?)?.toDouble(),
      );
}

/// The totals of the accounts whose cost is known.
class TreasuryTotals {
  const TreasuryTotals({
    required this.costedUsd,
    required this.bookValue,
    required this.uncosted,
    this.unrealized,
  });

  final double costedUsd;
  final double bookValue;

  /// The sum over the accounts that have one; null when none has.
  final double? unrealized;

  /// Accounts holding dollars whose opening cost is not set yet.
  final int uncosted;

  /// The average cost of all the costed dollars (book value ÷ dollars).
  double? get averageCost => costedUsd > 0 ? bookValue / costedUsd : null;

  factory TreasuryTotals.of(List<TreasuryPosition> rows) {
    var usd = 0.0;
    var value = 0.0;
    var uncosted = 0;
    double? unrealized;
    for (final p in rows) {
      if (p.hasCost) {
        usd += p.balance;
        value += p.bookValue ?? 0;
      } else if (p.balance > 0) {
        uncosted++;
      }
      if (p.unrealized != null) unrealized = (unrealized ?? 0) + p.unrealized!;
    }
    return TreasuryTotals(
      costedUsd: usd,
      bookValue: value,
      uncosted: uncosted,
      unrealized: unrealized,
    );
  }
}
