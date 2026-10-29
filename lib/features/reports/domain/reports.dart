/// The reports computed by the database (migration 0095): one period
/// (`report_period`) and the ageing of the customers' debts
/// (`report_debt_aging`). Dinars of the cash book and of the bank book are
/// shown apart; a total adds them as the owner asked.
library;

double _d(Object? v) => (v as num? ?? 0).toDouble();
int _i(Object? v) => (v as num? ?? 0).toInt();
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

/// One book's figures of the period.
class BookFigures {
  const BookFigures({
    required this.book,
    required this.saleN,
    required this.saleUsd,
    required this.saleLyd,
    required this.saleRatedUsd,
    required this.pricedUsd,
    required this.pricedLyd,
    required this.cogs,
    required this.profit,
    required this.unpricedN,
    required this.buyN,
    required this.buyUsd,
    required this.buyLyd,
    required this.buyRatedUsd,
    required this.usdStart,
    required this.usdEnd,
  });

  final String book;
  final int saleN;
  final double saleUsd;
  final double saleLyd;
  final double saleRatedUsd;

  /// The sales with a rate and a cost: the ones the profit is known of.
  final double pricedUsd;
  final double pricedLyd;
  final double cogs;
  final double profit;

  /// Sales without a rate or a cost (older builds): out of the profit.
  final int unpricedN;
  final int buyN;
  final double buyUsd;
  final double buyLyd;
  final double buyRatedUsd;
  final double usdStart;
  final double usdEnd;

  /// Dinars per dollar, on average; null when nothing to average.
  double? get avgSellRate => saleRatedUsd > 0 ? saleLyd / saleRatedUsd : null;
  double? get avgBuyRate => buyRatedUsd > 0 ? buyLyd / buyRatedUsd : null;
  double? get avgCostSold => pricedUsd > 0 ? cogs / pricedUsd : null;

  /// The profit of one dollar sold.
  double? get marginPerUsd => pricedUsd > 0 ? profit / pricedUsd : null;

  factory BookFigures.fromJson(Map<String, dynamic> j) => BookFigures(
        book: j['book'] as String,
        saleN: _i(j['sale_n']),
        saleUsd: _d(j['sale_usd']),
        saleLyd: _d(j['sale_lyd']),
        saleRatedUsd: _d(j['sale_rated_usd']),
        pricedUsd: _d(j['priced_usd']),
        pricedLyd: _d(j['priced_lyd']),
        cogs: _d(j['cogs']),
        profit: _d(j['profit']),
        unpricedN: _i(j['unpriced_n']),
        buyN: _i(j['buy_n']),
        buyUsd: _d(j['buy_usd']),
        buyLyd: _d(j['buy_lyd']),
        buyRatedUsd: _d(j['buy_rated_usd']),
        usdStart: _d(j['usd_start']),
        usdEnd: _d(j['usd_end']),
      );
}

/// The dinars of the box and of the bank at the start and at the end.
class LydFigures {
  const LydFigures({
    required this.open,
    this.cashStart = 0,
    this.cashEnd = 0,
    this.bankStart = 0,
    this.bankEnd = 0,
  });

  /// False until the dinar treasury was opened.
  final bool open;
  final double cashStart;
  final double cashEnd;
  final double bankStart;
  final double bankEnd;

  factory LydFigures.fromJson(Map<String, dynamic>? j) => LydFigures(
        open: j?['open'] as bool? ?? false,
        cashStart: _d(j?['cash_start']),
        cashEnd: _d(j?['cash_end']),
        bankStart: _d(j?['bank_start']),
        bankEnd: _d(j?['bank_end']),
      );
}

/// Sales, purchases and profit of a group (a day, an account, an employee).
class GroupFigures {
  const GroupFigures({
    required this.label,
    this.sub,
    this.book,
    this.day,
    required this.saleN,
    required this.saleUsd,
    required this.saleLyd,
    required this.buyN,
    required this.buyUsd,
    required this.buyLyd,
    required this.profit,
    this.creditGiven = 0,
    this.cancelledN = 0,
  });

  final String label;
  final String? sub;
  final String? book;
  final DateTime? day;
  final int saleN;
  final double saleUsd;
  final double saleLyd;
  final int buyN;
  final double buyUsd;
  final double buyLyd;
  final double profit;
  final double creditGiven;
  final int cancelledN;

  int get operations => saleN + buyN;

  static GroupFigures _base(
    Map<String, dynamic> j, {
    required String label,
    String? sub,
    String? book,
    DateTime? day,
  }) =>
      GroupFigures(
        label: label,
        sub: sub,
        book: book,
        day: day,
        saleN: _i(j['sale_n']),
        saleUsd: _d(j['sale_usd']),
        saleLyd: _d(j['sale_lyd']),
        buyN: _i(j['buy_n']),
        buyUsd: _d(j['buy_usd']),
        buyLyd: _d(j['buy_lyd']),
        profit: _d(j['profit']),
        creditGiven: _d(j['credit_given']),
        cancelledN: _i(j['cancelled_n']),
      );

  factory GroupFigures.day(Map<String, dynamic> j) {
    final day = DateTime.parse(j['day'] as String);
    return _base(j, label: '', day: day);
  }

  factory GroupFigures.account(Map<String, dynamic> j) => _base(
        j,
        label: (j['account'] as String?) ?? '',
        sub: j['company'] as String?,
        book: j['book'] as String?,
      );

  factory GroupFigures.employee(Map<String, dynamic> j) =>
      _base(j, label: (j['name'] as String?) ?? '—');
}

class PeriodReport {
  const PeriodReport({
    required this.from,
    required this.to,
    required this.books,
    required this.lyd,
    required this.previousSaleN,
    required this.previousSaleUsd,
    required this.previousBuyN,
    required this.previousBuyUsd,
    required this.previousProfit,
    required this.byDay,
    required this.byAccount,
    required this.byEmployee,
    required this.creditGiven,
    required this.creditTaken,
    required this.creditCollected,
    required this.creditPaid,
    required this.owedToUs,
    required this.weOwe,
    required this.cancelledN,
    required this.cancelledSaleUsd,
    required this.cancelledBuyUsd,
  });

  final DateTime from;
  final DateTime to;

  /// cash then bank.
  final List<BookFigures> books;
  final LydFigures lyd;
  final int previousSaleN;
  final double previousSaleUsd;
  final int previousBuyN;
  final double previousBuyUsd;
  final double previousProfit;
  final List<GroupFigures> byDay;
  final List<GroupFigures> byAccount;
  final List<GroupFigures> byEmployee;
  final double creditGiven;
  final double creditTaken;
  final double creditCollected;
  final double creditPaid;
  final double owedToUs;
  final double weOwe;
  final int cancelledN;
  final double cancelledSaleUsd;
  final double cancelledBuyUsd;

  double _sum(double Function(BookFigures b) f) =>
      books.fold<double>(0, (s, b) => s + f(b));

  int get saleN => books.fold<int>(0, (s, b) => s + b.saleN);
  int get buyN => books.fold<int>(0, (s, b) => s + b.buyN);
  double get saleUsd => _sum((b) => b.saleUsd);
  double get buyUsd => _sum((b) => b.buyUsd);
  double get saleLyd => _sum((b) => b.saleLyd);
  double get buyLyd => _sum((b) => b.buyLyd);
  double get profit => _sum((b) => b.profit);
  int get unpricedN => books.fold<int>(0, (s, b) => s + b.unpricedN);

  bool get isEmpty => saleN == 0 && buyN == 0;

  /// The change against the previous period, as a share (0.25 = +25 %);
  /// null when the previous one had nothing.
  static double? change(double now, double before) =>
      before.abs() < 0.005 ? null : (now - before) / before.abs();

  factory PeriodReport.fromJson(Map<String, dynamic> j) {
    final prev = j['previous'] as Map<String, dynamic>? ?? const {};
    final credit = j['credit'] as Map<String, dynamic>? ?? const {};
    final creditEnd = j['credit_end'] as Map<String, dynamic>? ?? const {};
    final cancels = j['cancels'] as Map<String, dynamic>? ?? const {};
    return PeriodReport(
      from: DateTime.parse(j['from'] as String),
      to: DateTime.parse(j['to'] as String),
      books: _list(j['books']).map(BookFigures.fromJson).toList(),
      lyd: LydFigures.fromJson(j['lyd'] as Map<String, dynamic>?),
      previousSaleN: _i(prev['sale_n']),
      previousSaleUsd: _d(prev['sale_usd']),
      previousBuyN: _i(prev['buy_n']),
      previousBuyUsd: _d(prev['buy_usd']),
      previousProfit: _d(prev['profit']),
      byDay: _list(j['by_day']).map(GroupFigures.day).toList(),
      byAccount: _list(j['by_account']).map(GroupFigures.account).toList(),
      byEmployee: _list(j['by_employee']).map(GroupFigures.employee).toList(),
      creditGiven: _d(credit['given']),
      creditTaken: _d(credit['taken']),
      creditCollected: _d(credit['collected']),
      creditPaid: _d(credit['paid']),
      owedToUs: _d(creditEnd['owed_to_us']),
      weOwe: _d(creditEnd['we_owe']),
      cancelledN: _i(cancels['n']),
      cancelledSaleUsd: _d(cancels['sale_usd']),
      cancelledBuyUsd: _d(cancels['buy_usd']),
    );
  }
}

/// One line of «كشف المديونيات»: a customer who owes us (a debtor) or whom
/// we owe (a creditor), with what is owed by age (the oldest debts are taken
/// as settled first), the last settlement (a collection from a debtor, a
/// payment to a creditor) and the last movement.
class DebtRow {
  const DebtRow({
    required this.clientId,
    required this.name,
    this.company,
    this.code,
    this.limit,
    required this.owed,
    required this.cash,
    required this.bank,
    required this.d7,
    required this.d30,
    required this.d90,
    required this.older,
    this.oldest,
    this.lastSettle,
    this.lastMove,
    this.overLimit = false,
  });

  final String clientId;
  final String name;
  final String? company;
  final String? code;

  /// The credit limit (debtors only); null: none.
  final double? limit;

  /// What is owed, always positive (the side tells who owes whom).
  final double owed;
  final double cash;
  final double bank;

  /// Up to 7 days, 8–30, 31–90, over 90.
  final double d7;
  final double d30;
  final double d90;
  final double older;
  final DateTime? oldest;
  final DateTime? lastSettle;
  final DateTime? lastMove;
  final bool overLimit;

  /// Owed for more than 30 days.
  double get late30 => d90 + older;

  /// Days since the last settlement, or since the oldest open debt when
  /// nothing was ever settled.
  int? daysWaiting(DateTime now) {
    final from = lastSettle ?? oldest;
    return from == null ? null : now.difference(from).inDays;
  }

  /// "name — company · code" for lists.
  String get title {
    final parts = [
      if (company != null && company!.trim().isNotEmpty) company!.trim(),
      if (code != null && code!.trim().isNotEmpty) code!.trim(),
    ];
    return parts.isEmpty ? name : '$name — ${parts.join(' · ')}';
  }

  static DateTime? _at(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory DebtRow.fromJson(Map<String, dynamic> j) => DebtRow(
        clientId: j['client_id'] as String,
        name: (j['name'] as String?) ?? '—',
        company: j['company'] as String?,
        code: j['code'] as String?,
        limit: (j['limit'] as num?)?.toDouble(),
        owed: _d(j['owed']),
        cash: _d(j['cash']),
        bank: _d(j['bank']),
        d7: _d(j['d7']),
        d30: _d(j['d30']),
        d90: _d(j['d90']),
        older: _d(j['older']),
        oldest: _at(j['oldest']),
        // 0095 sent only last_collect (debtors)
        lastSettle: _at(j['last_settle'] ?? j['last_collect']),
        lastMove: _at(j['last_move']),
        overLimit: j['over_limit'] as bool? ?? false,
      );
}

class DebtAging {
  const DebtAging({required this.debtors, required this.creditors});

  /// They owe us, the oldest debts first.
  final List<DebtRow> debtors;

  /// We owe them.
  final List<DebtRow> creditors;

  static double _sum(List<DebtRow> rows, double Function(DebtRow r) f) =>
      rows.fold<double>(0, (s, r) => s + f(r));

  double get owedToUs => _sum(debtors, (r) => r.owed);
  double get weOwe => _sum(creditors, (r) => r.owed);
  double get net => owedToUs - weOwe;
  double get d7 => _sum(debtors, (r) => r.d7);
  double get d30 => _sum(debtors, (r) => r.d30);
  double get d90 => _sum(debtors, (r) => r.d90);
  double get older => _sum(debtors, (r) => r.older);
  int get overLimit => debtors.where((d) => d.overLimit).length;

  factory DebtAging.fromJson(Map<String, dynamic> j) => DebtAging(
        debtors: _list(j['debtors']).map(DebtRow.fromJson).toList(),
        creditors: _list(j['creditors']).map(DebtRow.fromJson).toList(),
      );
}
