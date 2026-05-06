/// Snapshot of `account_licenses` for the current user, as returned by the
/// `current_license_status()` RPC.
class LicenseStatus {
  const LicenseStatus({
    required this.status,
    required this.licenseType,
    required this.trialEndsAt,
    required this.isValid,
    required this.isAdmin,
  });

  /// One of: pending, trial, active, expired, blocked.
  final String status;

  /// One of: trial, lifetime. Null while pending.
  final String? licenseType;

  /// Trial cutoff (UTC). Null for non-trial states.
  final DateTime? trialEndsAt;

  /// Server's authoritative answer: may the user enter the app?
  /// True iff `status='active'` OR (`status='trial'` AND `trial_ends_at > now()`).
  final bool isValid;

  /// Whether the current user has admin privileges. Drives the Admin entry
  /// in Settings and is enforced server-side by the admin_* RPCs.
  final bool isAdmin;

  bool get isPending => status == 'pending';
  bool get isBlocked => status == 'blocked';
  bool get isExpiredTrial =>
      status == 'expired' || (status == 'trial' && !isValid);

  factory LicenseStatus.fromJson(Map<String, dynamic> j) {
    return LicenseStatus(
      status: j['status'] as String,
      licenseType: j['license_type'] as String?,
      trialEndsAt: j['trial_ends_at'] == null
          ? null
          : DateTime.parse(j['trial_ends_at'] as String),
      isValid: j['is_valid'] as bool? ?? false,
      // Default false so cached rows from before 0014 don't break.
      isAdmin: j['is_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'license_type': licenseType,
        'trial_ends_at': trialEndsAt?.toIso8601String(),
        'is_valid': isValid,
        'is_admin': isAdmin,
      };

  /// Fallback when the RPC returns no row. Treated as pending so the gate
  /// keeps the user on the activation screen until the row materialises.
  static const LicenseStatus missing = LicenseStatus(
    status: 'pending',
    licenseType: null,
    trialEndsAt: null,
    isValid: false,
    isAdmin: false,
  );
}
