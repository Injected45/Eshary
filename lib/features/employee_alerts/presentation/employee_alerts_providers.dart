import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee_alerts_repository.dart';
import '../domain/employee_alert.dart';

/// Every alert about an employee's operation, newest first (admin only).
final employeeAlertsProvider = FutureProvider<List<EmployeeAlert>>((ref) {
  return ref.watch(employeeAlertsRepositoryProvider).listAlerts();
});

/// Alerts not yet opened — drives the badge in the settings list.
final unreadAlertsCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(employeeAlertsProvider).valueOrNull;
  if (alerts == null) return 0;
  return alerts.where((a) => !a.isRead).length;
});

/// What the admin has sent (one row per recipient), newest first.
final sentMessagesProvider = FutureProvider<List<EmployeeMessage>>((ref) {
  return ref.watch(employeeAlertsRepositoryProvider).listSentMessages();
});

/// The signed-in employee's inbox.
final employeeInboxProvider = FutureProvider<List<EmployeeMessage>>((ref) {
  return ref.watch(employeeAlertsRepositoryProvider).listInbox();
});

final unreadInboxCountProvider = Provider<int>((ref) {
  final msgs = ref.watch(employeeInboxProvider).valueOrNull;
  if (msgs == null) return 0;
  return msgs.where((m) => !m.isRead).length;
});
