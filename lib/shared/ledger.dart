/// One line of an accountant-style statement.
typedef LedgerLine = ({double? income, double? outgoing, double balance});

/// Turns the operations, oldest first, into statement lines: an entry fills
/// the دخول column, an exit the خروج column, and الرصيد is the running total
/// (entries add, exits subtract), e.g. دخول 1000, خروج 350 → الرصيد 650.
List<LedgerLine> ledgerOf(List<({bool isIncome, double amount})> ops) {
  var balance = 0.0;
  final lines = <LedgerLine>[];
  for (final op in ops) {
    balance += op.isIncome ? op.amount : -op.amount;
    lines.add((
      income: op.isIncome ? op.amount : null,
      outgoing: op.isIncome ? null : op.amount,
      balance: balance,
    ));
  }
  return lines;
}
