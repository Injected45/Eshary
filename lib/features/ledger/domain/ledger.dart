/// The general ledger (migration 0092): a double-entry journal in dinars
/// derived from the app's records, and the statements built on it.
library;

double _d(Object? v) => (v as num? ?? 0).toDouble();

/// The groups of the chart of accounts, by the first digit of the code.
enum LedgerGroup { asset, equity, income, expense }

LedgerGroup ledgerGroupOf(String account) => switch (account[0]) {
      '1' => LedgerGroup.asset,
      '3' => LedgerGroup.equity,
      '4' => LedgerGroup.income,
      _ => LedgerGroup.expense,
    };

/// One account of the trial balance.
class TrialLine {
  const TrialLine({
    required this.account,
    required this.name,
    required this.debit,
    required this.credit,
  });

  final String account;
  final String name;
  final double debit;
  final double credit;

  /// Debit − credit: + a debit balance.
  double get balance => debit - credit;

  factory TrialLine.fromJson(Map<String, dynamic> j) => TrialLine(
        account: j['account'] as String,
        name: (j['name'] as String?) ?? j['account'] as String,
        debit: _d(j['debit']),
        credit: _d(j['credit']),
      );
}

/// The trial balance's two totals, in cents (they must be equal).
({double debit, double credit}) trialTotals(List<TrialLine> lines) {
  var d = 0;
  var c = 0;
  for (final l in lines) {
    d += (l.debit * 100).round();
    c += (l.credit * 100).round();
  }
  return (debit: d / 100, credit: c / 100);
}

/// One line of the income statement: + income, − expense.
class IncomeLine {
  const IncomeLine({
    required this.account,
    required this.name,
    required this.amount,
  });

  final String account;
  final String name;
  final double amount;

  factory IncomeLine.fromJson(Map<String, dynamic> j) => IncomeLine(
        account: j['account'] as String,
        name: (j['name'] as String?) ?? j['account'] as String,
        amount: _d(j['amount']),
      );
}

class IncomeStatement {
  const IncomeStatement({required this.lines, required this.net});

  final List<IncomeLine> lines;

  /// + profit, − loss.
  final double net;

  List<IncomeLine> get income => [
        for (final l in lines)
          if (l.amount > 0) l
      ];
  List<IncomeLine> get expenses => [
        for (final l in lines)
          if (l.amount < 0) l
      ];

  factory IncomeStatement.fromJson(Map<String, dynamic> j) => IncomeStatement(
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            IncomeLine.fromJson(l as Map<String, dynamic>),
        ],
        net: _d(j['net']),
      );
}

/// An account's dollars: the ledger's value against balance × cost now. The
/// difference is the rounding of the weighted average, cent by cent.
class InventoryCheck {
  const InventoryCheck({
    required this.exchangeId,
    required this.companyName,
    required this.accountName,
    required this.balance,
    this.costRate,
    this.bookValue,
    required this.ledgerValue,
  });

  final String exchangeId;
  final String companyName;
  final String accountName;
  final double balance;
  final double? costRate;
  final double? bookValue;
  final double ledgerValue;

  double? get difference => bookValue == null
      ? null
      : ((ledgerValue - bookValue!) * 100).round() / 100;

  factory InventoryCheck.fromJson(Map<String, dynamic> j) => InventoryCheck(
        exchangeId: j['exchange_id'] as String,
        companyName: (j['company_name'] as String?) ?? '',
        accountName: (j['account_name'] as String?) ?? '',
        balance: _d(j['balance']),
        costRate: (j['cost_rate'] as num?)?.toDouble(),
        bookValue: (j['book_value'] as num?)?.toDouble(),
        ledgerValue: _d(j['ledger_value']),
      );
}

/// The balance sheet at a moment. [balances] holds every account's debit
/// balance (+ debit, − credit) and 'profit' (the income accounts to date,
/// as a balance: − a profit).
class BalanceSheet {
  const BalanceSheet({
    required this.balances,
    required this.receivable,
    required this.payable,
    required this.inventory,
  });

  final Map<String, double> balances;

  /// What customers owe us, and what we owe sellers (both positive).
  final double receivable;
  final double payable;
  final List<InventoryCheck> inventory;

  double of(String account) => balances[account] ?? 0;

  double get cash => of('1100');
  double get bank => of('1110');
  double get dollarsAtCost => of('1300');
  double get unvalued => of('1390');

  double get totalAssets =>
      _cents(cash + bank + receivable + dollarsAtCost + unvalued);

  /// The owner's equity: capital and openings, revaluation, cash outside
  /// the treasury, and the profit to date (accounts are credit balances).
  double get capital => -of('3100');
  double get revaluation => -of('3150');
  double get outsideTreasury => -of('3200');
  double get profitToDate => -of('profit');
  double get totalEquity =>
      _cents(capital + revaluation + outsideTreasury + profitToDate);

  /// Liabilities + equity: equal to the assets when the books balance.
  double get totalLiabilitiesAndEquity => _cents(payable + totalEquity);

  factory BalanceSheet.fromJson(Map<String, dynamic> j) => BalanceSheet(
        balances: {
          for (final e in ((j['balances'] as Map?) ?? const {}).entries)
            e.key as String: _d(e.value),
        },
        receivable: _d(j['receivable']),
        payable: _d(j['payable']),
        inventory: [
          for (final i in (j['inventory'] as List? ?? const []))
            InventoryCheck.fromJson(i as Map<String, dynamic>),
        ],
      );
}

double _cents(double v) => (v * 100).round() / 100;

/// One journal line (+ debit, − credit).
class JournalLine {
  const JournalLine({
    required this.at,
    required this.source,
    this.sourceId,
    this.ref,
    this.memo,
    required this.account,
    required this.name,
    required this.amount,
    this.exchange,
    this.client,
  });

  final DateTime at;
  final String source;
  final String? sourceId;
  final String? ref;
  final String? memo;
  final String account;
  final String name;
  final double amount;
  final String? exchange;
  final String? client;

  /// What made the entry, in words.
  String get sourceLabel => switch (source) {
        'sale' => 'بيع',
        'sale_cancel' => 'إلغاء بيع',
        'buy' => 'شراء',
        'buy_cancel' => 'إلغاء شراء',
        'cost_opening' => 'تكلفة افتتاحية',
        'cost_correction' => 'تصحيح التكلفة',
        'adjustment' => 'تسوية رصيد',
        'expense' => 'عمولة',
        'expense_cancel' => 'إلغاء عمولة',
        'customer_collect' => 'تحصيل من عميل',
        'customer_pay' => 'سداد لعميل',
        'customer_opening' => 'رصيد افتتاحي لعميل',
        'lyd_opening' => 'افتتاح خزينة الدينار',
        'lyd_in' => 'إيداع',
        'lyd_out' => 'سحب',
        'lyd_cash_to_bank' => 'من الصندوق إلى المصرف',
        'lyd_bank_to_cash' => 'من المصرف إلى الصندوق',
        'lyd_count_over' => 'زيادة جرد',
        'lyd_count_short' => 'عجز جرد',
        _ => source,
      };

  factory JournalLine.fromJson(Map<String, dynamic> j) => JournalLine(
        at: DateTime.parse(j['at'] as String),
        source: j['source'] as String,
        sourceId: j['source_id'] as String?,
        ref: j['ref'] as String?,
        memo: j['memo'] as String?,
        account: j['account'] as String,
        name: (j['name'] as String?) ?? j['account'] as String,
        amount: _d(j['amount']),
        exchange: j['exchange'] as String?,
        client: j['client'] as String?,
      );
}

class Journal {
  const Journal({required this.total, required this.lines});

  /// Every line in the period; [lines] holds at most 3000 of them.
  final int total;
  final List<JournalLine> lines;

  bool get cut => total > lines.length;

  factory Journal.fromJson(Map<String, dynamic> j) => Journal(
        total: (j['total'] as num? ?? 0).toInt(),
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            JournalLine.fromJson(l as Map<String, dynamic>),
        ],
      );
}

/// A closed period: the trial balance sealed at [periodEnd].
class PeriodClose {
  const PeriodClose({
    required this.id,
    required this.periodEnd,
    required this.netProfit,
    this.note,
    this.closedBy,
    required this.intact,
  });

  final String id;
  final DateTime periodEnd;
  final double netProfit;
  final String? note;
  final String? closedBy;

  /// False when the books up to [periodEnd] no longer give the sealed trial
  /// balance (a restore changed the past).
  final bool intact;

  factory PeriodClose.fromJson(Map<String, dynamic> j) => PeriodClose(
        id: j['id'] as String,
        periodEnd: DateTime.parse(j['period_end'] as String),
        netProfit: _d(j['net_profit']),
        note: j['note'] as String?,
        closedBy: j['closed_by'] as String?,
        intact: j['intact'] as bool? ?? false,
      );
}

/// An account compared with the exchange company's statement.
class Reconciliation {
  const Reconciliation({
    required this.at,
    required this.theirBalance,
    required this.ourBalance,
    required this.difference,
    this.note,
  });

  final DateTime at;
  final double theirBalance;
  final double ourBalance;

  /// Theirs − ours.
  final double difference;
  final String? note;

  bool get matches => difference.abs() < 0.005;

  factory Reconciliation.fromJson(Map<String, dynamic> j) => Reconciliation(
        at: DateTime.parse(j['at'] as String),
        theirBalance: _d(j['their_balance']),
        ourBalance: _d(j['our_balance']),
        difference: _d(j['difference']),
        note: j['note'] as String?,
      );
}
