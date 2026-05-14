enum ActivityEventType {
  login,
  logout,
  transferCreated,
  currencyBuyCreated,
  pendingBuyCreated,
  unknown,
}

ActivityEventType _parseEventType(String raw) {
  switch (raw) {
    case 'login':
      return ActivityEventType.login;
    case 'logout':
      return ActivityEventType.logout;
    case 'transfer_created':
      return ActivityEventType.transferCreated;
    case 'currency_buy_created':
      return ActivityEventType.currencyBuyCreated;
    case 'pending_buy_created':
      return ActivityEventType.pendingBuyCreated;
    default:
      return ActivityEventType.unknown;
  }
}

String activityEventLabel(ActivityEventType t) {
  switch (t) {
    case ActivityEventType.login:
      return 'تسجيل دخول';
    case ActivityEventType.logout:
      return 'تسجيل خروج';
    case ActivityEventType.transferCreated:
      return 'إنشاء حوالة خروج';
    case ActivityEventType.currencyBuyCreated:
      return 'إنشاء حوالة دخول';
    case ActivityEventType.pendingBuyCreated:
      return 'دخول قيد التنفيذ';
    case ActivityEventType.unknown:
      return 'حدث غير معروف';
  }
}

class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.parentAdminId,
    required this.subUserId,
    required this.sessionId,
    required this.eventType,
    required this.operationId,
    required this.amount,
    required this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String parentAdminId;
  final String subUserId;
  final String? sessionId;
  final ActivityEventType eventType;
  final String? operationId;
  final double? amount;
  final String? deviceId;
  final DateTime createdAt;

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        id: json['id'] as String,
        parentAdminId: json['parent_admin_id'] as String,
        subUserId: json['sub_user_id'] as String,
        sessionId: json['session_id'] as String?,
        eventType: _parseEventType(json['event_type'] as String),
        operationId: json['operation_id'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        deviceId: json['device_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
