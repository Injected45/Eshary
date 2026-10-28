/// The dinar treasury (migration 0086): one cash box and one bank account,
/// from the opening the administrator typed. Computed by the database:
///   cash = opening + exits paid in cash − entries paid in cash ± movements
class LydSummary {
  const LydSummary({
    required this.open,
    this.startedAt,
    this.openingCash = 0,
    this.openingBank = 0,
    this.cash = 0,
    this.bank = 0,
    this.salesCash = 0,
    this.salesBank = 0,
    this.buysCash = 0,
    this.buysBank = 0,
    this.movements = const [],
    this.counts = const [],
  });

  /// False until the administrator typed the opening balances.
  final bool open;
  final DateTime? startedAt;
  final double openingCash;
  final double openingBank;

  /// What the box and the bank hold now.
  final double cash;
  final double bank;

  /// The period's dinars: received for dollars sold (exits) and paid for
  /// dollars bought (entries), by pocket.
  final double salesCash;
  final double salesBank;
  final double buysCash;
  final double buysBank;

  /// The period's deposits, withdrawals, transfers and count differences.
  final List<LydMovement> movements;

  /// The last end-of-day counts, newest first.
  final List<LydCount> counts;

  double get total => _cents(cash + bank);
  double get netCash => _cents(salesCash - buysCash);
  double get netBank => _cents(salesBank - buysBank);

  factory LydSummary.fromJson(Map<String, dynamic> j) {
    if (j['open'] != true) return const LydSummary(open: false);
    double d(Object? v) => (v as num? ?? 0).toDouble();
    final f = (j['flows'] as Map<String, dynamic>?) ?? const {};
    return LydSummary(
      open: true,
      startedAt: j['started_at'] == null
          ? null
          : DateTime.parse(j['started_at'] as String),
      openingCash: d(j['opening_cash']),
      openingBank: d(j['opening_bank']),
      cash: d(j['cash']),
      bank: d(j['bank']),
      salesCash: d(f['sales_cash']),
      salesBank: d(f['sales_bank']),
      buysCash: d(f['buys_cash']),
      buysBank: d(f['buys_bank']),
      movements: [
        for (final m in (j['movements'] as List? ?? const []))
          LydMovement.fromJson(m as Map<String, dynamic>),
      ],
      counts: [
        for (final c in (j['counts'] as List? ?? const []))
          LydCount.fromJson(c as Map<String, dynamic>),
      ],
    );
  }
}

class LydMovement {
  const LydMovement({
    required this.kind,
    required this.pocket,
    required this.amount,
    required this.note,
    required this.createdAt,
  });

  /// in, out, cash_to_bank, bank_to_cash, count_over, count_short.
  final String kind;

  /// cash / bank for "in" and "out"; null otherwise.
  final String? pocket;
  final double amount;
  final String? note;
  final DateTime createdAt;

  String get label => switch (kind) {
        'in' => pocket == 'bank' ? 'إيداع في المصرف' : 'إيداع في الصندوق',
        'out' => pocket == 'bank' ? 'سحب من المصرف' : 'سحب من الصندوق',
        'cash_to_bank' => 'من الصندوق إلى المصرف',
        'bank_to_cash' => 'من المصرف إلى الصندوق',
        'count_over' => 'زيادة جرد',
        'count_short' => 'عجز جرد',
        _ => kind,
      };

  /// Adds to the treasury as a whole (a transfer between pockets adds nothing).
  bool get isIn => kind == 'in' || kind == 'count_over';
  bool get isOut => kind == 'out' || kind == 'count_short';

  factory LydMovement.fromJson(Map<String, dynamic> j) => LydMovement(
        kind: j['kind'] as String,
        pocket: j['pocket'] as String?,
        amount: (j['amount'] as num).toDouble(),
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class LydCount {
  const LydCount({
    required this.expected,
    required this.counted,
    required this.difference,
    required this.posted,
    required this.note,
    required this.createdAt,
  });

  final double expected;
  final double counted;

  /// counted − expected: positive is a surplus, negative a shortage.
  final double difference;

  /// The difference was booked into the box.
  final bool posted;
  final String? note;
  final DateTime createdAt;

  factory LydCount.fromJson(Map<String, dynamic> j) => LydCount(
        expected: (j['expected'] as num).toDouble(),
        counted: (j['counted'] as num).toDouble(),
        difference: (j['difference'] as num).toDouble(),
        posted: j['posted'] as bool? ?? false,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

double _cents(double v) => (v * 100).round() / 100;
