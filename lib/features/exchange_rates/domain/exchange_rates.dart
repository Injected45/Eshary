/// The administrator's last rates (dinars per dollar) and whether the caller
/// may type another rate, per kind of operation (migrations 0081, 0083).
///
/// [sell] is the rate of the last exit (we sell dollars), [buy] of the last
/// entry (we buy dollars). Null until the administrator saved one.
class ExchangeRates {
  /// [canEdit] sets both kinds at once; [canEditSell] / [canEditBuy] override
  /// it for one kind.
  const ExchangeRates({
    required this.sell,
    required this.buy,
    bool? canEdit,
    bool? canEditSell,
    bool? canEditBuy,
  })  : canEditSell = canEditSell ?? canEdit ?? false,
        canEditBuy = canEditBuy ?? canEdit ?? false;

  final double? sell;
  final double? buy;

  /// The administrator, or an employee granted "rate_edit_sell": types the
  /// sell rate of an exit. Everyone else saves at the administrator's last
  /// sell rate (the database enforces it).
  final bool canEditSell;

  /// The same for the buy rate of an entry ("rate_edit_buy").
  final bool canEditBuy;

  /// Whether the rate of an exit ([sell]) or of an entry may be typed.
  bool canEditFor({required bool sell}) => sell ? canEditSell : canEditBuy;

  /// The administrator's last rate of that kind.
  double? lastFor({required bool sell}) => sell ? this.sell : buy;

  factory ExchangeRates.fromJson(Map<String, dynamic> json) {
    // a database before 0083 sends one flag for both
    final both = json['can_edit'] as bool? ?? false;
    return ExchangeRates(
      sell: (json['sell'] as num?)?.toDouble(),
      buy: (json['buy'] as num?)?.toDouble(),
      canEditSell: json['can_edit_sell'] as bool? ?? both,
      canEditBuy: json['can_edit_buy'] as bool? ?? both,
    );
  }
}
