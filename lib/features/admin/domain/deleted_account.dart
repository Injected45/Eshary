/// One entry of the log of deleted accounts (`admin_list_deleted_accounts`).
class DeletedAccount {
  const DeletedAccount({
    required this.id,
    required this.email,
    required this.phone,
    required this.licenseStatus,
    required this.accountCreated,
    required this.companies,
    required this.clients,
    required this.employees,
    required this.deletedByEmail,
    required this.deletedAt,
  });

  final String id;
  final String email;
  final String? phone;

  /// pending / trial / active / blocked / expired — the state it had.
  final String licenseStatus;
  final DateTime? accountCreated;

  /// How much setup data went with it.
  final int companies;
  final int clients;
  final int employees;
  final String? deletedByEmail;
  final DateTime deletedAt;

  String get statusLabel => switch (licenseStatus) {
        'active' => 'مفعّل',
        'trial' => 'تجريبي',
        'blocked' => 'محظور',
        'expired' => 'منتهي',
        _ => 'بانتظار التفعيل',
      };

  factory DeletedAccount.fromJson(Map<String, dynamic> j) => DeletedAccount(
        id: j['id'] as String,
        email: (j['email'] as String?) ?? '—',
        phone: j['phone'] as String?,
        licenseStatus: (j['license_status'] as String?) ?? 'pending',
        accountCreated: j['account_created'] == null
            ? null
            : DateTime.parse(j['account_created'] as String).toLocal(),
        companies: (j['companies'] as num?)?.toInt() ?? 0,
        clients: (j['clients'] as num?)?.toInt() ?? 0,
        employees: (j['employees'] as num?)?.toInt() ?? 0,
        deletedByEmail: j['deleted_by_email'] as String?,
        deletedAt: DateTime.parse(j['deleted_at'] as String).toLocal(),
      );
}
