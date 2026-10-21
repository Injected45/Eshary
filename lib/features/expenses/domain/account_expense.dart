/// A one-sided deduction from an account (migration 0072): the commission an
/// exchange company charges for managing the account, or any other expense of
/// that account. No other party, no message. Never edited or deleted; a mistake
/// is cancelled the same day and the record keeps its values.
class AccountExpense {
  const AccountExpense({
    required this.id,
    required this.exchangeId,
    required this.amount,
    required this.code,
    required this.note,
    required this.createdAt,
    required this.createdByName,
    this.cancelledAt,
    this.cancelReason,
  });

  final String id;
  final String exchangeId;
  final double amount;

  /// The number / code written with the commission (optional).
  final String? code;

  /// What the commission is for.
  final String note;
  final DateTime createdAt;
  final String createdByName;
  final DateTime? cancelledAt;
  final String? cancelReason;

  bool get isCancelled => cancelledAt != null;

  /// What it counts for in a total: nothing once cancelled.
  double get netAmount => isCancelled ? 0 : amount;

  factory AccountExpense.fromJson(Map<String, dynamic> j) => AccountExpense(
        id: j['id'] as String,
        exchangeId: j['exchange_id'] as String,
        amount: (j['amount'] as num).toDouble(),
        code: j['code'] as String?,
        note: (j['note'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        createdByName: (j['created_by_name'] as String?) ?? 'المدير',
        cancelledAt: j['cancelled_at'] == null
            ? null
            : DateTime.parse(j['cancelled_at'] as String),
        cancelReason: j['cancel_reason'] as String?,
      );

  /// "كود C-77 · عمولة": the line shown in lists and statements.
  String get label {
    final c = (code ?? '').trim();
    return c.isEmpty ? note : 'كود $c · $note';
  }
}
