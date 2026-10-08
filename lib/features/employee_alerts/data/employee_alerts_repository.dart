import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/employee_alert.dart';

/// Reads and updates the two notification flows between admin and employees
/// (see 0045_employee_notifications.sql). Alerts are written by a database
/// trigger; messages are sent through an RPC. Neither is cached offline —
/// they are only useful live.
class EmployeeAlertsRepository {
  EmployeeAlertsRepository(this._client);
  final SupabaseClient _client;

  // ---- admin: alerts about employees' operations ---------------------------

  Future<List<EmployeeAlert>> listAlerts() async {
    final rows = await _client
        .from('admin_alerts')
        .select()
        .order('created_at', ascending: false)
        .limit(2000);
    return (rows as List)
        .map((r) => EmployeeAlert.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAlertsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('admin_alerts')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', ids)
        .isFilter('read_at', null);
  }

  Future<void> deleteAlerts(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.from('admin_alerts').delete().inFilter('id', ids);
  }

  // ---- admin: messages to employees ----------------------------------------

  /// [subUserIds] null (or empty) = every active employee. Returns how many
  /// employees received it.
  Future<int> sendMessage({
    required List<String>? subUserIds,
    required String? title,
    required String body,
  }) async {
    final res = await _client.rpc<dynamic>(
      'admin_send_employee_message',
      params: {
        'p_sub_user_ids': subUserIds,
        'p_title': title,
        'p_body': body,
      },
    );
    return (res as num).toInt();
  }

  Future<List<EmployeeMessage>> listSentMessages() async {
    final rows = await _client
        .from('employee_messages')
        .select()
        .order('created_at', ascending: false)
        .limit(1000);
    return (rows as List)
        .map((r) => EmployeeMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteMessages(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.from('employee_messages').delete().inFilter('id', ids);
  }

  // ---- employee: own inbox -------------------------------------------------

  Future<List<EmployeeMessage>> listInbox() async {
    final rows = await _client
        .from('employee_messages')
        .select()
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List)
        .map((r) => EmployeeMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> markInboxRead([List<String>? ids]) async {
    await _client.rpc<dynamic>(
      'employee_mark_messages_read',
      params: {'p_ids': ids},
    );
  }
}

final employeeAlertsRepositoryProvider =
    Provider<EmployeeAlertsRepository>((ref) {
  return EmployeeAlertsRepository(ref.watch(supabaseClientProvider));
});
