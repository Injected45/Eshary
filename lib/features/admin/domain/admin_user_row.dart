/// One row in the admin users table — what `admin_list_users()` returns.
class AdminUserRow {
  const AdminUserRow({
    required this.userId,
    required this.email,
    required this.status,
    required this.licenseType,
    required this.trialEndsAt,
    required this.isAdmin,
    required this.createdAt,
  });

  final String userId;
  final String email;
  final String status;
  final String? licenseType;
  final DateTime? trialEndsAt;
  final bool isAdmin;
  final DateTime createdAt;

  /// Mirrors the is_valid logic from current_license_status() so the admin
  /// list renders the same colour as the user's own pending screen.
  bool get isValid =>
      status == 'active' ||
      (status == 'trial' &&
          trialEndsAt != null &&
          trialEndsAt!.isAfter(DateTime.now().toUtc()));

  factory AdminUserRow.fromJson(Map<String, dynamic> j) {
    return AdminUserRow(
      userId: j['user_id'] as String,
      email: (j['email'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'pending',
      licenseType: j['license_type'] as String?,
      trialEndsAt: j['trial_ends_at'] == null
          ? null
          : DateTime.parse(j['trial_ends_at'] as String),
      isAdmin: j['is_admin'] as bool? ?? false,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}
