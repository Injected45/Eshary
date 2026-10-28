/// A documented change of an account's dollar balance (تسوية رصيد, migration
/// 0086): the administrator, a reason and the password. Append-only; shown in
/// the account statement. The dollars move at cost (the cost price stays).
class BalanceAdjustment {
  const BalanceAdjustment({
    required this.id,
    required this.exchangeId,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.delta,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String exchangeId;
  final double balanceBefore;
  final double balanceAfter;

  /// balanceAfter − balanceBefore: positive adds dollars, negative removes.
  final double delta;
  final String reason;
  final DateTime createdAt;

  /// The line in the account statement.
  String get label => 'تسوية رصيد: $reason';

  factory BalanceAdjustment.fromJson(Map<String, dynamic> j) =>
      BalanceAdjustment(
        id: j['id'] as String,
        exchangeId: j['exchange_id'] as String,
        balanceBefore: (j['balance_before'] as num).toDouble(),
        balanceAfter: (j['balance_after'] as num).toDouble(),
        delta: (j['delta'] as num).toDouble(),
        reason: (j['reason'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// What admin_adjust_balance answered.
sealed class AdjustResult {
  const AdjustResult();
}

class AdjustDone extends AdjustResult {
  const AdjustDone(this.balanceAfter);
  final double balanceAfter;
}

class AdjustWrongPassword extends AdjustResult {
  const AdjustWrongPassword(this.remaining);

  /// Tries left before the password is locked for 15 minutes (shared with the
  /// cancellations).
  final int remaining;
}

class AdjustLocked extends AdjustResult {
  const AdjustLocked();
}

class AdjustPasswordNotSet extends AdjustResult {
  const AdjustPasswordNotSet();
}

AdjustResult parseAdjustResult(Map<String, dynamic> r) {
  if (r['ok'] == true) {
    return AdjustDone((r['balance_after'] as num).toDouble());
  }
  switch (r['error']) {
    case 'wrong_password':
      return AdjustWrongPassword((r['remaining'] as num? ?? 0).toInt());
    case 'locked':
      return const AdjustLocked();
    default:
      return const AdjustPasswordNotSet();
  }
}
