import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Quick boolean for "is the caller currently acting as an employee?".
/// Used throughout the workflow screens (TransfersScreen, CurrencyBuyScreen)
/// to hide admin-only affordances like the archive button.
final isEmployeeProvider = Provider<bool>((ref) {
  return ref.watch(currentEmployeeProvider).value != null;
});
