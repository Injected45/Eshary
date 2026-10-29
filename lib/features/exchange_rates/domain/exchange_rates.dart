/// The administrator's last rates (dinars per dollar) and whether the caller
/// may type another rate, per kind of operation (migrations 0081, 0083).
///
/// [sell] is the rate of the last sale (we sell dollars), [buy] of the last
/// purchase. Since 0093 each kind has a rate per book: [sell] / [buy] are the
/// CASH book's, [sellBank] / [buyBank] the BANK book's (Libya prices the
/// dollar differently in cash dinars and in bank dinars). Null until the
/// administrator saved one.
class ExchangeRates {
  /// [canEdit] sets both kinds at once; [canEditSell] / [canEditBuy] override
  /// it for one kind.
  const ExchangeRates({
    required this.sell,
    required this.buy,
    this.sellBank,
    this.buyBank,
    bool? canEdit,
    bool? canEditSell,
    bool? canEditBuy,
  })  : canEditSell = canEditSell ?? canEdit ?? false,
        canEditBuy = canEditBuy ?? canEdit ?? false;

  final double? sell;
  final double? buy;
  final double? sellBank;
  final double? buyBank;

  /// The administrator, or an employee granted "rate_edit_sell": types the
  /// sell rate of an exit. Everyone else saves at the administrator's last
  /// sell rate (the database enforces it).
  final bool canEditSell;

  /// The same for the buy rate of an entry ("rate_edit_buy").
  final bool canEditBuy;

  /// Whether the rate of an exit ([sell]) or of an entry may be typed.
  bool canEditFor({required bool sell}) => sell ? canEditSell : canEditBuy;

  /// The administrator's last rate of that kind, in that book ('cash' or
  /// 'bank').
  double? lastFor({required bool sell, String book = 'cash'}) =>
      book == 'bank' ? (sell ? sellBank : buyBank) : (sell ? this.sell : buy);

  factory ExchangeRates.fromJson(Map<String, dynamic> json) {
    // a database before 0083 sends one flag for both
    final both = json['can_edit'] as bool? ?? false;
    // 0093 sends the four rates; before it, one per kind (then both books).
    // A key that is THERE but null means no rate of that book yet: it must
    // not fall back to the other book's rate (a new subscriber's bank rate
    // would show the cash one).
    double? pick(String key, String old) =>
        ((json.containsKey(key) ? json[key] : json[old]) as num?)?.toDouble();
    return ExchangeRates(
      sell: pick('sell_cash', 'sell'),
      buy: pick('buy_cash', 'buy'),
      sellBank: pick('sell_bank', 'sell'),
      buyBank: pick('buy_bank', 'buy'),
      canEditSell: json['can_edit_sell'] as bool? ?? both,
      canEditBuy: json['can_edit_buy'] as bool? ?? both,
    );
  }
}
