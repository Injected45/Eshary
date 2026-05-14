import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee_auth_repository.dart';

/// Resolves the active employee identity (or null) for the current
/// anonymous session. Watched by the router and by the employee home
/// screen to decide what to render.
final currentEmployeeProvider = FutureProvider<EmployeeIdentity?>((ref) async {
  return ref.watch(employeeAuthRepositoryProvider).currentIdentity();
});

/// Quick boolean for "is the caller currently acting as an employee?".
/// Used throughout the workflow screens (TransfersScreen, CurrencyBuyScreen)
/// to hide admin-only affordances like the archive button.
final isEmployeeProvider = Provider<bool>((ref) {
  return ref.watch(currentEmployeeProvider).value != null;
});
