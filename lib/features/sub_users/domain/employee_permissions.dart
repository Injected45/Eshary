/// Permissions an admin can grant to an employee (sub_users.permissions).
///
/// The keys are enforced by the database (record_* / archive_* functions and
/// row-level security, migration 0041). A new employee has none: they see an
/// empty app until the admin grants some. This list must match
/// `_employee_permission_keys()` in the database.
class EmployeePermission {
  const EmployeePermission({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
  });

  final String key;
  final String label;
  final String description;
  final String group;
}

const String kPermTransfersCreate = 'transfers_create';
const String kPermBuysCreate = 'buys_create';
const String kPermViewOwn = 'view_own';
const String kPermViewAll = 'view_all';
const String kPermArchiveTransfers = 'archive_transfers';
const String kPermArchiveBuys = 'archive_buys';
const String kPermArchiveAll = 'archive_all';
const String kPermClosingsOwn = 'closings_own';
const String kPermClosingsAll = 'closings_all';
const String kPermAccountsOwn = 'accounts_own';
const String kPermAccountsAll = 'accounts_all';

const List<EmployeePermission> kEmployeePermissions = [
  EmployeePermission(
    key: kPermTransfersCreate,
    label: 'تنفيذ خروج حوالة',
    description: 'تظهر له شاشة الخروج ويستطيع التنفيذ، ويرى عمليات اليوم التي نفّذها هو.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermBuysCreate,
    label: 'تنفيذ دخول حوالة',
    description: 'تظهر له شاشة الدخول ويستطيع التنفيذ، ويرى عمليات اليوم التي نفّذها هو.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermViewOwn,
    label: 'عرض سجل عملياتي',
    description: 'يرى سجل كل ما نفّذه هو فقط، اليومي والمقفل، ولا يرى عمليات غيره.',
    group: 'العرض',
  ),
  EmployeePermission(
    key: kPermViewAll,
    label: 'عرض جميع العمليات',
    description: 'يرى عمليات كل الموظفين والمدير، اليومية والمقفلة. بدونها لا يرى إلا عملياته.',
    group: 'العرض',
  ),
  EmployeePermission(
    key: kPermArchiveTransfers,
    label: 'الإقفال اليومي للخروج',
    description: 'يقفل حوالات الخروج التي نفّذها هو فقط (يخصم من الأرصدة).',
    group: 'الإقفال',
  ),
  EmployeePermission(
    key: kPermArchiveBuys,
    label: 'الإقفال اليومي للدخول',
    description: 'يقفل حوالات الدخول التي نفّذها هو فقط (يضيف إلى الأرصدة).',
    group: 'الإقفال',
  ),
  EmployeePermission(
    key: kPermArchiveAll,
    label: 'الإقفال لعمليات الجميع',
    description: 'مع صلاحية الإقفال أعلاه، يقفل عمليات كل الموظفين والمدير بدل عملياته فقط.',
    group: 'الإقفال',
  ),
  EmployeePermission(
    key: kPermClosingsOwn,
    label: 'الإقفالات: إقفالاتي فقط',
    description: 'يظهر له قسم الإقفالات (باليوم أو بفترة) ويرى إقفالات عملياته هو فقط.',
    group: 'الإقفالات',
  ),
  EmployeePermission(
    key: kPermClosingsAll,
    label: 'الإقفالات: جميع الإقفالات',
    description: 'يظهر له قسم الإقفالات ويرى إقفالات الجميع. تتضمن الاطلاع على أسماء الحسابات.',
    group: 'الإقفالات',
  ),
  EmployeePermission(
    key: kPermAccountsOwn,
    label: 'حسابي: ما نفّذته أنا فقط',
    description: 'يظهر له قسم حسابي بملخص ما نفّذه هو على كل حساب، بدون الأرصدة.',
    group: 'الحساب',
  ),
  EmployeePermission(
    key: kPermAccountsAll,
    label: 'حسابي: الحساب كاملاً',
    description: 'يظهر له قسم حسابي كاملاً بكل الحسابات والأرصدة.',
    group: 'الحساب',
  ),
];

/// Arabic label for [key], or the key itself if unknown.
String employeePermissionLabel(String key) {
  for (final p in kEmployeePermissions) {
    if (p.key == key) return p.label;
  }
  return key;
}
