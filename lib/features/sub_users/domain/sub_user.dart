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
    required this.permissions,
    required this.status,
    required this.deviceId,
    required this.branchId,
    required this.lastLoginAt,
    required this.createdAt,
    this.googleEmail,
  });

  final String id;
  final String parentAdminId;
  final String employeeName;
  final String phoneNumber;
  final bool loginCodeUsed;
  /// Granted permissions (keys from employee_permissions.dart). Empty for a
  /// new employee: they see an empty app until the admin grants some.
  final List<String> permissions;
  final SubUserStatus status;
  final String? deviceId;
  final String? branchId;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  /// Google e-mail the employee picked on their device. Informational: it is
  /// reported by the device, not verified by the server.
  final String? googleEmail;

  factory SubUser.fromJson(Map<String, dynamic> json) => SubUser(
        id: json['id'] as String,
        parentAdminId: json['parent_admin_id'] as String,
        employeeName: json['employee_name'] as String,
        phoneNumber: json['phone_number'] as String,
        loginCodeUsed: (json['login_code_used'] as bool?) ?? false,
        permissions: ((json['permissions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        status: _parseStatus(json['status'] as String),
        deviceId: json['device_id'] as String?,
        branchId: json['branch_id'] as String?,
        lastLoginAt: json['last_login_at'] == null
            ? null
            : DateTime.parse(json['last_login_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        googleEmail: json['google_email'] as String?,
      );
}
