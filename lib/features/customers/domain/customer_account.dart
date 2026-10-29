/// A customer's dinar account (migration 0091): what he owes us (+) for
/// dollars sold on credit, or what we owe him (−) for dollars bought on
/// credit, his later payments, and the limit the administrator set.
class CustomerBalance {
  const CustomerBalance({
    required this.clientId,
    required this.name,
    this.company,
    this.code,
    this.creditLimit,
    required this.balance,
    this.lastAt,
  });

  final String clientId;
  final String name;
  final String? company;
  final String? code;

  /// The most he may owe us. Null: no credit for him.
  final double? creditLimit;

  /// + he owes us; − we owe him.
  final double balance;
  final DateTime? lastAt;

  /// "name / company", the way the app names a party.
  String get title => [
        name,
        if ((company ?? '').trim().isNotEmpty) company!.trim(),
      ].join(' / ');

  bool get overLimit => balance > (creditLimit ?? 0) && balance > 0;

  factory CustomerBalance.fromJson(Map<String, dynamic> j) => CustomerBalance(
        clientId: j['client_id'] as String,
        name: (j['name'] as String?) ?? '—',
        company: j['company'] as String?,
        code: j['code'] as String?,
        creditLimit: (j['credit_limit'] as num?)?.toDouble(),
        balance: (j['balance'] as num? ?? 0).toDouble(),
        lastAt: j['last_at'] == null
            ? null
            : DateTime.parse(j['last_at'] as String),
      );
}

/// Every customer's total: what customers owe us and what we owe sellers.
class CustomerTotals {
  const CustomerTotals({required this.receivable, required this.payable});

  /// The sum of the positive balances: owed to us.
  final double receivable;

  /// The sum of the negative balances, as a positive figure: we owe.
  final double payable;

  factory CustomerTotals.of(List<CustomerBalance> all) {
    var cents = 0;
    var owe = 0;
    for (final c in all) {
      final v = (c.balance * 100).round();
      if (v > 0) cents += v;
      if (v < 0) owe -= v;
    }
    return CustomerTotals(receivable: cents / 100, payable: owe / 100);
  }
}

/// One line of a customer's dinar statement.
class CustomerEntry {
  const CustomerEntry({
    required this.id,
    required this.kind,
    required this.amount,
    this.pocket,
    this.note,
    required this.createdAt,
    this.reference,
    this.usd,
    this.rate,
    this.lyd,
  });

  final String id;

  /// sale, buy, sale_cancel, buy_cancel, collect, pay, opening.
  final String kind;

  /// + he owes us more; − he owes us less (or we owe him).
  final double amount;
  final String? pocket;
  final String? note;
  final DateTime createdAt;

  /// The operation behind a sale / purchase line.
  final String? reference;
  final double? usd;
  final double? rate;
  final double? lyd;

  String get label => switch (kind) {
        'sale' => 'بيع بالآجل',
        'buy' => 'شراء بالآجل',
        'sale_cancel' => 'إلغاء بيع',
        'buy_cancel' => 'إلغاء شراء',
        'collect' => 'تحصيل منه',
        'pay' => 'سداد له',
        'opening' => 'رصيد افتتاحي',
        _ => kind,
      };

  factory CustomerEntry.fromJson(Map<String, dynamic> j) => CustomerEntry(
        id: j['id'] as String,
        kind: j['kind'] as String,
        amount: (j['amount'] as num).toDouble(),
        pocket: j['pocket'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        reference: j['reference'] as String?,
        usd: (j['usd'] as num?)?.toDouble(),
        rate: (j['rate'] as num?)?.toDouble(),
        lyd: (j['lyd'] as num?)?.toDouble(),
      );
}

/// A customer's statement for a period: the balance before it, its lines,
/// and the balance now.
class CustomerStatement {
  const CustomerStatement({
    required this.opening,
    required this.closing,
    required this.entries,
  });

  final double opening;
  final double closing;
  final List<CustomerEntry> entries;

  /// The running balance after each line, from [opening], in cents.
  List<double> get running {
    var cents = (opening * 100).round();
    return [
      for (final e in entries) (cents += (e.amount * 100).round()) / 100,
    ];
  }

  factory CustomerStatement.fromJson(Map<String, dynamic> j) =>
      CustomerStatement(
        opening: (j['opening'] as num? ?? 0).toDouble(),
        closing: (j['closing'] as num? ?? 0).toDouble(),
        entries: [
          for (final e in (j['entries'] as List? ?? const []))
            CustomerEntry.fromJson(e as Map<String, dynamic>),
        ],
      );
}

/// "لنا 500.00 د.ل" / "علينا 255.00 د.ل" / "مسدَّد".
String customerBalanceLabel(double balance, String Function(num) money) {
  if (balance.abs() < 0.005) return 'مسدَّد';
  return balance > 0
      ? 'لنا ${money(balance)} د.ل'
      : 'علينا ${money(-balance)} د.ل';
}
