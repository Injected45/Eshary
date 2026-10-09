/// Which table a cancelled operation lives in.
enum OperationKind { transfer, buy }

OperationKind _parseKind(String s) =>
    s == 'buy' ? OperationKind.buy : OperationKind.transfer;

String operationKindToDb(OperationKind k) =>
    k == OperationKind.buy ? 'buy' : 'transfer';

/// خروج / دخول.
String operationKindLabel(OperationKind k) =>
    k == OperationKind.buy ? 'دخول' : 'خروج';

/// One cancellation as recorded by `admin_cancel_operation` (0048). The row
/// is append-only: nobody can edit or delete it from the app.
class OperationCancellation {
  const OperationCancellation({
    required this.id,
    required this.kind,
    required this.operationId,
    required this.companyName,
    required this.exchangeName,
    required this.exchangeCode,
    required this.amount,
    required this.reference,
    required this.partyName,
    required this.operationCreatedAt,
    required this.operationEmployeeName,
    required this.requestedByName,
    required this.reason,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.cancelledByName,
    required this.cancelledAt,
  });

  final String id;
  final OperationKind kind;
  final String operationId;

  /// حسابي (e.g. الرحالة الأولى).
  final String? companyName;

  /// The exchange company holding the account (e.g. بهار روز).
  final String? exchangeName;
  final String? exchangeCode;
  final double amount;
  final String? reference;
  final String? partyName;
  final DateTime operationCreatedAt;

  /// Who executed the operation ('المدير' for the admin).
  final String operationEmployeeName;

  /// The employee who asked for it, when it came from a request.
  final String? requestedByName;
  final String reason;
  final double balanceBefore;
  final double balanceAfter;
  final String cancelledByName;
  final DateTime cancelledAt;

  String get kindLabel => operationKindLabel(kind);

  /// "الرحالة الأولى - بهار روز".
  String get accountLabel =>
      '${companyName ?? '—'} - ${exchangeName ?? '—'}';

  factory OperationCancellation.fromJson(Map<String, dynamic> j) =>
      OperationCancellation(
        id: j['id'] as String,
        kind: _parseKind(j['kind'] as String),
        operationId: j['operation_id'] as String,
        companyName: j['company_name'] as String?,
        exchangeName: j['exchange_name'] as String?,
        exchangeCode: j['exchange_code'] as String?,
        amount: (j['amount'] as num).toDouble(),
        reference: j['reference'] as String?,
        partyName: j['party_name'] as String?,
        operationCreatedAt:
            DateTime.parse(j['operation_created_at'] as String).toLocal(),
        operationEmployeeName:
            (j['operation_employee_name'] as String?) ?? '—',
        requestedByName: j['requested_by_name'] as String?,
        reason: (j['reason'] as String?) ?? '',
        balanceBefore: (j['balance_before'] as num).toDouble(),
        balanceAfter: (j['balance_after'] as num).toDouble(),
        cancelledByName: (j['cancelled_by_name'] as String?) ?? '—',
        cancelledAt: DateTime.parse(j['cancelled_at'] as String).toLocal(),
      );
}

enum CancelRequestStatus { pending, approved, rejected }

CancelRequestStatus _parseStatus(String s) {
  switch (s) {
    case 'approved':
      return CancelRequestStatus.approved;
    case 'rejected':
      return CancelRequestStatus.rejected;
    default:
      return CancelRequestStatus.pending;
  }
}

/// An employee's request to cancel one of their own operations of today.
class CancellationRequest {
  const CancellationRequest({
    required this.id,
    required this.subUserId,
    required this.employeeName,
    required this.kind,
    required this.operationId,
    required this.amount,
    required this.partyName,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.decidedAt,
    required this.decisionNote,
  });

  final String id;
  final String? subUserId;
  final String employeeName;
  final OperationKind kind;
  final String operationId;
  final double amount;
  final String? partyName;
  final String reason;
  final CancelRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decisionNote;

  bool get isPending => status == CancelRequestStatus.pending;
  String get kindLabel => operationKindLabel(kind);

  /// A request can only be approved the same day as the operation (Libya
  /// date); after midnight it is left without effect.
  bool isExpiredAt(DateTime now) => isPending && !isSameDay(createdAt, now);

  factory CancellationRequest.fromJson(Map<String, dynamic> j) =>
      CancellationRequest(
        id: j['id'] as String,
        subUserId: j['sub_user_id'] as String?,
        employeeName: (j['employee_name'] as String?) ?? '—',
        kind: _parseKind(j['kind'] as String),
        operationId: j['operation_id'] as String,
        amount: (j['amount'] as num).toDouble(),
        partyName: j['party_name'] as String?,
        reason: (j['reason'] as String?) ?? '',
        status: _parseStatus(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        decidedAt: j['decided_at'] == null
            ? null
            : DateTime.parse(j['decided_at'] as String).toLocal(),
        decisionNote: j['decision_note'] as String?,
      );
}

/// Same calendar day, by the phone's date. The database decides by the date
/// in Libya; this only hides buttons that would be refused anyway.
bool isSameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// An operation can be cancelled only on the day it was made, and once.
bool canCancelToday({
  required DateTime createdAt,
  required DateTime? cancelledAt,
  DateTime? now,
}) =>
    cancelledAt == null && isSameDay(createdAt, now ?? DateTime.now());

/// The outcome of `admin_cancel_operation`.
sealed class CancelResult {
  const CancelResult();
}

class CancelDone extends CancelResult {
  const CancelDone(this.balanceAfter);
  final double balanceAfter;
}

class CancelWrongPassword extends CancelResult {
  const CancelWrongPassword(this.remaining);

  /// Tries left before cancelling is locked for 15 minutes.
  final int remaining;
}

class CancelLocked extends CancelResult {
  const CancelLocked();
}

class CancelPasswordNotSet extends CancelResult {
  const CancelPasswordNotSet();
}

CancelResult parseCancelResult(Map<String, dynamic> r) {
  if (r['ok'] == true) {
    return CancelDone((r['balance_after'] as num?)?.toDouble() ?? 0);
  }
  switch (r['error']) {
    case 'wrong_password':
      return CancelWrongPassword((r['remaining'] as num?)?.toInt() ?? 0);
    case 'password_not_set':
      return const CancelPasswordNotSet();
    default:
      return const CancelLocked();
  }
}
