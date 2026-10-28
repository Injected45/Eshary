enum AlertKind {
  transfer,
  buy,
  pendingBuy,

  /// An employee asks the admin to cancel one of their exits / entries.
  cancelRequestTransfer,
  cancelRequestBuy,
}

AlertKind _parseKind(String s) {
  switch (s) {
    case 'buy':
      return AlertKind.buy;
    case 'pending_buy':
      return AlertKind.pendingBuy;
    case 'cancel_request_transfer':
      return AlertKind.cancelRequestTransfer;
    case 'cancel_request_buy':
      return AlertKind.cancelRequestBuy;
    default:
      return AlertKind.transfer;
  }
}

/// An operation an employee saved, as reported to the admin.
class EmployeeAlert {
  const EmployeeAlert({
    required this.id,
    required this.subUserId,
    required this.employeeName,
    required this.kind,
    required this.operationId,
    required this.amount,
    required this.partyName,
    required this.createdAt,
    required this.readAt,
  });

  final String id;

  /// Null once the employee has been deleted; [employeeName] still holds
  /// the name they had.
  final String? subUserId;
  final String employeeName;
  final AlertKind kind;
  final String operationId;
  final double amount;
  final String? partyName;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  bool get isCancelRequest =>
      kind == AlertKind.cancelRequestTransfer ||
      kind == AlertKind.cancelRequestBuy;

  /// The operation was an exit (transfer), not an entry.
  bool get isExit =>
      kind == AlertKind.transfer || kind == AlertKind.cancelRequestTransfer;

  /// خروج (transfer) or دخول (currency buy).
  String get directionLabel => isExit ? 'خروج' : 'دخول';

  /// The counterpart: المستفيد for an exit, العميل for an entry.
  String get partyLabel => isExit ? 'المستفيد' : 'العميل';

  factory EmployeeAlert.fromJson(Map<String, dynamic> json) => EmployeeAlert(
        id: json['id'] as String,
        subUserId: json['sub_user_id'] as String?,
        employeeName: (json['employee_name'] as String?) ?? '—',
        kind: _parseKind(json['kind'] as String),
        operationId: json['operation_id'] as String,
        amount: (json['amount'] as num).toDouble(),
        partyName: json['party_name'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}

/// A message the admin sent to one employee (one row per recipient).
class EmployeeMessage {
  const EmployeeMessage({
    required this.id,
    required this.subUserId,
    required this.broadcastId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final String subUserId;
  final String broadcastId;
  final String? title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory EmployeeMessage.fromJson(Map<String, dynamic> json) =>
      EmployeeMessage(
        id: json['id'] as String,
        subUserId: json['sub_user_id'] as String,
        broadcastId: json['broadcast_id'] as String,
        title: json['title'] as String?,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
