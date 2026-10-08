import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sub_users/domain/employee_permissions.dart';
import '../data/employee_auth_repository.dart';

/// Resolves the active employee identity (or null) for the current
/// anonymous session. Watched by the router and by the employee home
/// screen to decide what to render.
final currentEmployeeProvider = FutureProvider<EmployeeIdentity?>((ref) async {
  return ref.watch(employeeAuthRepositoryProvider).currentIdentity();
});

/// The employee's own work per account, for the "حسابي" tab (accounts_own).
final employeeMyAccountProvider =
    FutureProvider.autoDispose<List<MyAccountRow>>((ref) {
  return ref.watch(employeeAuthRepositoryProvider).myAccount();
});

/// Permissions of the signed-in employee (empty for admins and while loading).
/// Use [canProvider] to ask about one key.
final employeePermissionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(currentEmployeeProvider).value?.permissions.toSet() ??
      const <String>{};
});

/// Whether the current user may do [key]. Admins (not employees) may do
/// everything; employees only what the admin granted. The database enforces
/// the same rule, this is only for showing / hiding things.
final canProvider = Provider.family<bool, String>((ref, key) {
  final identity = ref.watch(currentEmployeeProvider).value;
  if (identity == null) return true;
  return identity.permissions.contains(key);
});

/// Which operation types an employee's screens show: (exits, entries).
///
/// The type follows what the employee is allowed to DO: executing or closing
/// exits shows exits, executing or closing entries shows entries, both shows
/// both. The "own / all" permissions (view, closings, account) only widen WHOSE
/// operations are shown, never which type. An employee holding only an "all"
/// permission and no execute / close permission (a pure viewer) sees both.
/// Admins see both. Display only: the database decides what can be read.
({bool exits, bool entries}) visibleTypesFor(Iterable<String>? permissions) {
  if (permissions == null) return (exits: true, entries: true); // admin
  final p = permissions.toSet();
  var exits = p.contains(kPermTransfersCreate) ||
      p.contains(kPermArchiveTransfers);
  var entries = p.contains(kPermBuysCreate) || p.contains(kPermArchiveBuys);
  if (!exits && !entries) {
    final viewer = p.contains(kPermViewAll) ||
        p.contains(kPermClosingsAll) ||
        p.contains(kPermAccountsAll) ||
        p.contains(kPermArchiveAll);
    if (viewer) {
      exits = true;
      entries = true;
    }
  }
  return (exits: exits, entries: entries);
}

/// Whether to show EXITS (خروج) / ENTRIES (دخول); see [visibleTypesFor].
final seesExitsProvider = Provider<bool>((ref) {
  final identity = ref.watch(currentEmployeeProvider).value;
  return visibleTypesFor(identity?.permissions).exits;
});

final seesEntriesProvider = Provider<bool>((ref) {
  final identity = ref.watch(currentEmployeeProvider).value;
  return visibleTypesFor(identity?.permissions).entries;
});

/// Quick boolean for "is the caller currently acting as an employee?".
/// Used throughout the workflow screens (TransfersScreen, CurrencyBuyScreen)
/// to hide admin-only affordances like the archive button.
final isEmployeeProvider = Provider<bool>((ref) {
  return ref.watch(currentEmployeeProvider).value != null;
});
