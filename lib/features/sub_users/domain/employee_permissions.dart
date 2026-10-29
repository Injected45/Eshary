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
const String kPermPartyLetters = 'party_letters';
const String kPermClientsAdd = 'clients_add';
const String kPermRateEditSell = 'rate_edit_sell';
const String kPermRateEditBuy = 'rate_edit_buy';

const List<EmployeePermission> kEmployeePermissions = [
  EmployeePermission(
    key: kPermTransfersCreate,
    label: 'تنفيذ بيع حوالة',
    description:
        'تظهر له شاشة البيع ويستطيع التنفيذ، ويرى رصيد الحساب الذي يحوّل منه ليعرف إن كان يكفي، ويرى عمليات اليوم التي نفّذها هو.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermBuysCreate,
    label: 'تنفيذ شراء حوالة',
    description:
        'تظهر له شاشة الشراء ويستطيع التنفيذ، ويرى عمليات اليوم التي نفّذها هو.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermViewOwn,
    label: 'عرض سجل عملياتي',
    description:
        'يرى سجل ما نفّذه هو فقط، من النوع المسموح له (بيع أو شراء أو الاثنين)، ولا يرى عمليات غيره.',
    group: 'العرض',
  ),
  EmployeePermission(
    key: kPermViewAll,
    label: 'عرض جميع العمليات',
    description:
        'يرى عمليات كل الموظفين والمدير، من النوع المسموح له (بيع أو شراء). بدونها لا يرى إلا عملياته.',
    group: 'العرض',
  ),
  EmployeePermission(
    key: kPermClosingsOwn,
    label: 'تبويب العمليات: عملياتي فقط',
    description:
        'يظهر له تبويب العمليات (باليوم أو بفترة) ويرى عملياته هو فقط.',
    group: 'تبويب العمليات',
  ),
  EmployeePermission(
    key: kPermClosingsAll,
    label: 'تبويب العمليات: جميع العمليات',
    description:
        'يظهر له تبويب العمليات ويرى عمليات الجميع. تتضمن الاطلاع على أسماء الحسابات.',
    group: 'تبويب العمليات',
  ),
  EmployeePermission(
    key: kPermAccountsOwn,
    label: 'حسابي: ما نفّذته أنا فقط',
    description:
        'يظهر له قسم حسابي بملخص ما نفّذه هو على كل حساب، بدون الأرصدة.',
    group: 'الحساب',
  ),
  EmployeePermission(
    key: kPermAccountsAll,
    label: 'حسابي: الحساب كاملاً',
    description: 'يظهر له قسم حسابي كاملاً بكل الحسابات والأرصدة.',
    group: 'الحساب',
  ),
  EmployeePermission(
    key: kPermPartyLetters,
    label: 'تعديل حروف الإشاري الثابتة',
    description:
        'يظهر له قلم بجانب الرقم الإشاري في شاشة الشراء ليضيف أو يغيّر الحروف الثابتة لإشاري الجهة المرسلة (مثل TRC). لا يستطيع تغيير أي شيء آخر في الجهة.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermClientsAdd,
    label: 'إضافة جهات محفوظة',
    description:
        'يستطيع إضافة جهة جديدة (مرسل أو مستفيد) من شاشتي الشراء والبيع. لا يستطيع تعديل الجهات الموجودة أو حذفها ولا إضافة شركات صرافة.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermRateEditSell,
    label: 'إدخال سعر البيع',
    description:
        'يكتب سعر البيع بنفسه في كل عملية بيع (مع صلاحية تنفيذ بيع حوالة). بدونها يُحفظ بيعه بآخر سعر بيع استخدمه المدير ولا يستطيع تغييره.',
    group: 'العمليات',
  ),
  EmployeePermission(
    key: kPermRateEditBuy,
    label: 'إدخال سعر الشراء',
    description:
        'يكتب سعر الشراء بنفسه في كل عملية شراء (مع صلاحية تنفيذ شراء حوالة). بدونها يُحفظ شراؤه بآخر سعر شراء استخدمه المدير ولا يستطيع تغييره.',
    group: 'العمليات',
  ),
];

/// Arabic label for [key], or the key itself if unknown.
String employeePermissionLabel(String key) {
  for (final p in kEmployeePermissions) {
    if (p.key == key) return p.label;
  }
  return key;
}
