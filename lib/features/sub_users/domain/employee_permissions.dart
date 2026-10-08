/// Permissions an admin can grant to an employee (sub_users.permissions).
///
/// The keys are enforced by the database (record_* functions and
/// row-level security, migrations 0041-0047). There is no daily-close
/// permission any more: an operation is posted when it is saved (0047). A new employee has none: they see an
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
const String kPermClosingsOwn = 'closings_own';
const String kPermClosingsAll = 'closings_all';
const String kPermAccountsOwn = 'accounts_own';
const String kPermAccountsAll = 'accounts_all';

const List<EmployeePermission> kEmployeePermissions = [
  EmployeePermission(
    key: kPermTransfersCreate,
    label: 'تنفيذ خروج حوالة',
    description: 'تظهر له شاشة الخروج ويستطيع التنفيذ، ويرى رصيد الحساب الذي يحوّل منه ليعرف إن كان يكفي، ويرى عمليات اليوم التي نفّذها هو.',
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
    description: 'يرى سجل ما نفّذه هو فقط، اليومي والمقفل، من النوع المسموح له (خروج أو دخول أو الاثنين)، ولا يرى عمليات غيره.',
    group: 'العرض',
  ),
  EmployeePermission(
    key: kPermViewAll,
    label: 'عرض جميع العمليات',
    description: 'يرى عمليات كل الموظفين والمدير، اليومية والمقفلة، من النوع المسموح له (خروج أو دخول). بدونها لا يرى إلا عملياته.',
    group: 'العرض',
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
