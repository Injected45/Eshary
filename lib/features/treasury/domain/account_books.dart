/// An account's two books (migration 0093): the dollars bought with CASH
/// dinars and the dollars bought with BANK dinars, each with its own
/// quantity and weighted-average cost (in its own dinars). In Libya the dollar
/// is priced differently in each, so the two are never mixed.
library;

double _d(Object? v) => (v as num? ?? 0).toDouble();

const String kBookCash = 'cash';
const String kBookBank = 'bank';

String bookLabel(String book) => book == kBookBank ? 'مصرفي' : 'نقدي';

/// One book of one account.
class BookPosition {
  const BookPosition({required this.balance, this.costRate, this.bookValue});

  final double balance;

  /// Dinars (of this book) per dollar. Null: no cost yet.
  final double? costRate;

  /// balance × cost, in this book's dinars.
  final double? bookValue;

  bool get hasDollars => balance.abs() >= 0.005;

  factory BookPosition.fromJson(Map<String, dynamic>? j) => BookPosition(
        balance: _d(j?['balance']),
        costRate: (j?['cost_rate'] as num?)?.toDouble(),
        bookValue: (j?['book_value'] as num?)?.toDouble(),
      );
}

class AccountBooks {
  const AccountBooks({
    required this.exchangeId,
    required this.companyName,
    required this.accountName,
    required this.balance,
    required this.split,
    required this.cash,
    required this.bank,
    this.marketSellCash,
    this.marketSellBank,
  });

  final String exchangeId;
  final String companyName;
  final String accountName;

  /// The account's dollars: cash + bank.
  final double balance;

  /// False until the administrator typed how the dollars held before 0093
  /// split between the books (they all start in the bank book).
  final bool split;
  final BookPosition cash;
  final BookPosition bank;

  /// The administrator's last sell rate of each book.
  final double? marketSellCash;
  final double? marketSellBank;

  BookPosition of(String book) => book == kBookBank ? bank : cash;

  factory AccountBooks.fromJson(Map<String, dynamic> j) => AccountBooks(
        exchangeId: j['exchange_id'] as String,
        companyName: (j['company_name'] as String?) ?? '',
        accountName: (j['account_name'] as String?) ?? '',
        balance: _d(j['balance']),
        split: j['split'] as bool? ?? false,
        cash: BookPosition.fromJson(j['cash'] as Map<String, dynamic>?),
        bank: BookPosition.fromJson(j['bank'] as Map<String, dynamic>?),
        marketSellCash: (j['market_sell_cash'] as num?)?.toDouble(),
        marketSellBank: (j['market_sell_bank'] as num?)?.toDouble(),
      );
}
