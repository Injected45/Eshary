/// One account's realized profit over a period (migration 0084): every exit
/// not cancelled, with a sell rate and the account's cost at that exit.
class ProfitRow {
  const ProfitRow({
    required this.exchangeId,
    required this.companyName,
    required this.accountName,
    required this.soldUsd,
    required this.salesLyd,
    required this.costLyd,
    required this.profitLyd,
    required this.exitsPriced,
    required this.exitsUnpriced,
    required this.unpricedUsd,
    required this.boughtUsd,
    required this.boughtLyd,
    required this.entriesPriced,
  });

  final String exchangeId;
  final String companyName;
  final String accountName;

  /// Dollars sold by exits that have both a rate and a cost.
  final double soldUsd;

  /// What those exits brought in, in dinars.
  final double salesLyd;

  /// What those dollars had cost (cost of goods sold), in dinars.
  final double costLyd;

  /// salesLyd − costLyd. Negative is a loss.
  final double profitLyd;
  final int exitsPriced;

  /// Exits without a rate or a cost: left out of the profit, never guessed.
  final int exitsUnpriced;
  final double unpricedUsd;

  /// Entries with a rate: dollars bought and the dinars paid for them.
  final double boughtUsd;
  final double boughtLyd;
  final int entriesPriced;

  factory ProfitRow.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num? ?? 0).toDouble();
    int i(String k) => (j[k] as num? ?? 0).toInt();
    return ProfitRow(
      exchangeId: j['exchange_id'] as String,
      companyName: (j['company_name'] as String?) ?? '',
      accountName: (j['account_name'] as String?) ?? '',
      soldUsd: d('sold_usd'),
      salesLyd: d('sales_lyd'),
      costLyd: d('cost_lyd'),
      profitLyd: d('profit_lyd'),
      exitsPriced: i('exits_priced'),
      exitsUnpriced: i('exits_unpriced'),
      unpricedUsd: d('unpriced_usd'),
      boughtUsd: d('bought_usd'),
      boughtLyd: d('bought_lyd'),
      entriesPriced: i('entries_priced'),
    );
  }
}

/// The period across all accounts, with the derived rates.
class ProfitTotals {
  const ProfitTotals({
    required this.soldUsd,
    required this.salesLyd,
    required this.costLyd,
    required this.exitsUnpriced,
    required this.unpricedUsd,
    required this.boughtUsd,
    required this.boughtLyd,
  });

  final double soldUsd;
  final double salesLyd;
  final double costLyd;
  final int exitsUnpriced;
  final double unpricedUsd;
  final double boughtUsd;
  final double boughtLyd;

  /// Summed from the rounded figures of the database, so it adds up exactly
  /// with what each account shows.
  double get profitLyd => _cents(salesLyd - costLyd);

  /// Average sell rate of the period (dinars received per dollar sold).
  double? get avgSellRate => soldUsd > 0 ? salesLyd / soldUsd : null;

  /// Average cost of the dollars sold.
  double? get avgCostRate => soldUsd > 0 ? costLyd / soldUsd : null;

  /// Profit per dollar sold (the spread actually earned).
  double? get marginPerUsd => soldUsd > 0 ? profitLyd / soldUsd : null;

  /// Profit as a share of the cost, in percent.
  double? get marginPercent => costLyd > 0 ? profitLyd / costLyd * 100 : null;

  /// Average buy rate of the period.
  double? get avgBuyRate => boughtUsd > 0 ? boughtLyd / boughtUsd : null;

  /// Dinars in from sales minus dinars out for purchases.
  double get netLydFlow => _cents(salesLyd - boughtLyd);

  factory ProfitTotals.of(List<ProfitRow> rows) {
    var sold = 0.0, sales = 0.0, cost = 0.0, unUsd = 0.0;
    var bought = 0.0, paid = 0.0;
    var un = 0;
    for (final r in rows) {
      sold += r.soldUsd;
      sales += r.salesLyd;
      cost += r.costLyd;
      un += r.exitsUnpriced;
      unUsd += r.unpricedUsd;
      bought += r.boughtUsd;
      paid += r.boughtLyd;
    }
    return ProfitTotals(
      soldUsd: _cents(sold),
      salesLyd: _cents(sales),
      costLyd: _cents(cost),
      exitsUnpriced: un,
      unpricedUsd: _cents(unUsd),
      boughtUsd: _cents(bought),
      boughtLyd: _cents(paid),
    );
  }
}

/// Sums of values that each have 2 decimals: back to whole dirhams, so the
/// binary fraction of a double never shows (0.1 + 0.2).
double _cents(double v) => (v * 100).round() / 100;

/// One change of an account's cost (account_cost_events, migration 0082).
class CostEvent {
  const CostEvent({
    required this.kind,
    required this.balanceBefore,
    required this.costBefore,
    required this.usdAmount,
    required this.rate,
    required this.balanceAfter,
    required this.costAfter,
    required this.createdAt,
  });

  /// opening, correction, buy, buy_cancel, sell_cancel (0084).
  final String kind;
  final double balanceBefore;
  final double? costBefore;
  final double? usdAmount;
  final double? rate;
  final double balanceAfter;
  final double costAfter;
  final DateTime createdAt;

  String get label => switch (kind) {
        'opening' => 'سعر أول المدة',
        'correction' => 'تصحيح السعر',
        'buy' => 'دخول',
        'buy_cancel' => 'إلغاء دخول',
        'sell_cancel' => 'إلغاء خروج',
        _ => kind,
      };

  factory CostEvent.fromJson(Map<String, dynamic> j) => CostEvent(
        kind: j['kind'] as String,
        balanceBefore: (j['balance_before'] as num).toDouble(),
        costBefore: (j['cost_before'] as num?)?.toDouble(),
        usdAmount: (j['usd_amount'] as num?)?.toDouble(),
        rate: (j['rate'] as num?)?.toDouble(),
        balanceAfter: (j['balance_after'] as num).toDouble(),
        costAfter: (j['cost_after'] as num).toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
