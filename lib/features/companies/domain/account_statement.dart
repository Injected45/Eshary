import '../../../shared/ledger.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../transfers/domain/transfer.dart';

/// Whose operations a statement covers.
enum StatementScope {
  /// Everything: the admin's and every employee's.
  all,

  /// Only what the admin did personally ("أنا").
  me,

  /// Only what one employee did.
  employee,
}

/// One line of an account statement: an entry (دخول) or an exit (خروج) with
/// the running balance after it.
class StatementEntry {
  const StatementEntry({
    required this.at,
    required this.income,
    required this.outgoing,
    required this.balance,
    required this.employeeId,
    required this.exchangeId,
  });

  final DateTime at;

  /// Set for an entry, null for an exit.
  final double? income;

  /// Set for an exit, null for an entry.
  final double? outgoing;

  /// Running balance after this line (entries add, exits subtract).
  final double balance;

  /// The employee who did it; null means the admin.
  final String? employeeId;
  final String exchangeId;

  bool get isIncome => income != null;
}

class AccountStatement {
  const AccountStatement({
    required this.entries,
    required this.totalIncome,
    required this.totalOutgoing,
  });

  final List<StatementEntry> entries;
  final double totalIncome;
  final double totalOutgoing;

  /// الرصيد: total entries minus total exits.
  double get balance => totalIncome - totalOutgoing;

  bool get isEmpty => entries.isEmpty;
}

/// Builds the short statement (دخول / خروج / الرصيد) from posted operations.
///
/// [start]..[end] bound the period (by the posting time). [scope] picks whose
/// operations to count; with [StatementScope.employee], [employeeId] names the
/// employee. [exchangeId] limits it to one account (null = all accounts).
/// The balance starts at zero at the beginning of the period.
AccountStatement buildAccountStatement({
  required List<CurrencyBuy> buys,
  required List<Transfer> transfers,
  required DateTime start,
  required DateTime end,
  StatementScope scope = StatementScope.all,
  String? employeeId,
  String? exchangeId,
}) {
  bool wanted(String? by, String exchange, DateTime at) {
    if (at.isBefore(start) || at.isAfter(end)) return false;
    if (exchangeId != null && exchange != exchangeId) return false;
    switch (scope) {
      case StatementScope.all:
        return true;
      case StatementScope.me:
        return by == null;
      case StatementScope.employee:
        return by != null && by == employeeId;
    }
  }

  final ops = <({
    DateTime at,
    bool isIncome,
    double amount,
    String? by,
    String exchange,
    String id,
  })>[
    for (final b in buys)
      if (wanted(b.createdByEmployeeId, b.exchangeId, b.archivedAt ?? b.createdAt))
        (
          at: b.archivedAt ?? b.createdAt,
          isIncome: true,
          amount: b.usdAmount,
          by: b.createdByEmployeeId,
          exchange: b.exchangeId,
          id: b.id,
        ),
    for (final t in transfers)
      if (wanted(t.createdByEmployeeId, t.exchangeId, t.archivedAt ?? t.createdAt))
        (
          at: t.archivedAt ?? t.createdAt,
          isIncome: false,
          amount: t.amount,
          by: t.createdByEmployeeId,
          exchange: t.exchangeId,
          id: t.id,
        ),
  ]..sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  final lines = ledgerOf([
    for (final o in ops) (isIncome: o.isIncome, amount: o.amount),
  ]);

  var income = 0.0;
  var outgoing = 0.0;
  for (final o in ops) {
    if (o.isIncome) {
      income += o.amount;
    } else {
      outgoing += o.amount;
    }
  }

  return AccountStatement(
    entries: [
      for (var i = 0; i < ops.length; i++)
        StatementEntry(
          at: ops[i].at,
          income: lines[i].income,
          outgoing: lines[i].outgoing,
          balance: lines[i].balance,
          employeeId: ops[i].by,
          exchangeId: ops[i].exchange,
        ),
    ],
    totalIncome: income,
    totalOutgoing: outgoing,
  );
}
