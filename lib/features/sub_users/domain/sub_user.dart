enum SubUserRole { entry, exit, both }

SubUserRole _parseRole(String s) {
  switch (s) {
    case 'entry':
      return SubUserRole.entry;
    case 'exit':
      return SubUserRole.exit;
    default:
      return SubUserRole.both;
  }
}

String subUserRoleToDb(SubUserRole r) {
  switch (r) {
    case SubUserRole.entry:
      return 'entry';
    case SubUserRole.exit:
      return 'exit';
    case SubUserRole.both:
      return 'both';
  }
}

String subUserRoleLabel(SubUserRole r) {
  switch (r) {
    case SubUserRole.entry:
      return 'دخول فقط';
    case SubUserRole.exit:
      return 'خروج فقط';
    case SubUserRole.both:
      return 'دخول وخروج';
  }
}

enum SubUserStatus { active, disabled }

SubUserStatus _parseStatus(String s) =>
    s == 'disabled' ? SubUserStatus.disabled : SubUserStatus.active;

String subUserStatusToDb(SubUserStatus s) =>
    s == SubUserStatus.disabled ? 'disabled' : 'active';

class SubUser {
  const SubUser({
    required this.id,
    required this.parentAdminId,
    required this.employeeName,
    required this.phoneNumber,
    required this.loginCodeUsed,
    required this.role,
    required this.status,
    required this.deviceId,
    required this.branchId,
    required this.lastLoginAt,
    required this.createdAt,
  });

  final String id;
  final String parentAdminId;
  final String employeeName;
  final String phoneNumber;
  final bool loginCodeUsed;
  final SubUserRole role;
  final SubUserStatus status;
  final String? deviceId;
  final String? branchId;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  factory SubUser.fromJson(Map<String, dynamic> json) => SubUser(
        id: json['id'] as String,
        parentAdminId: json['parent_admin_id'] as String,
        employeeName: json['employee_name'] as String,
        phoneNumber: json['phone_number'] as String,
        loginCodeUsed: (json['login_code_used'] as bool?) ?? false,
        role: _parseRole(json['role'] as String),
        status: _parseStatus(json['status'] as String),
        deviceId: json['device_id'] as String?,
        branchId: json['branch_id'] as String?,
        lastLoginAt: json['last_login_at'] == null
            ? null
            : DateTime.parse(json['last_login_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
