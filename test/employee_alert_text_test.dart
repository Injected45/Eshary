import 'dart:io';

import 'package:eshary/features/employee_alerts/domain/employee_alert.dart';
import 'package:eshary/features/employee_alerts/presentation/employee_alerts_screen.dart';
import 'package:flutter_test/flutter_test.dart';

EmployeeAlert _alert(String kind, {String? party = 'أحمد', double amount = 1250}) {
  return EmployeeAlert.fromJson({
    'id': 'a1',
    'sub_user_id': 's1',
    'employee_name': 'سامي',
    'kind': kind,
    'operation_id': 'o1',
    'amount': amount,
    'party_name': party,
    'created_at': '2026-10-08T12:00:00Z',
    'read_at': null,
  });
}

void main() {
  test('exit alert reads: تم تنفيذ "خروج" من الموظف … بقيمة … إلى المستفيد', () {
    final text = alertText(_alert('transfer'));
    expect(text, contains('تم تنفيذ "خروج" من الموظف سامي'));
    expect(text, contains('بقيمة 1,250.00\$ إلى المستفيد أحمد'));
  });

  test('entry alert says دخول and العميل; pending is an entry too', () {
    expect(alertText(_alert('buy')), contains('"دخول"'));
    expect(alertText(_alert('buy')), contains('إلى العميل'));
    final p = _alert('pending_buy');
    expect(p.kind, AlertKind.pendingBuy);
    expect(p.directionLabel, 'دخول');
  });

  test('a missing party shows a dash instead of "null"', () {
    expect(alertText(_alert('transfer', party: null)), isNot(contains('null')));
    expect(alertText(_alert('transfer', party: '  ')), contains('المستفيد —'));
  });

  test('unread until read_at is set', () {
    expect(_alert('transfer').isRead, isFalse);
  });

  test('the migration keeps the table and both functions the app calls', () {
    final sql = File('supabase/migrations/0045_employee_notifications.sql')
        .readAsStringSync();
    for (final name in [
      'admin_alerts',
      'employee_messages',
      'admin_send_employee_message',
      'employee_mark_messages_read',
    ]) {
      expect(sql, contains(name));
    }
  });
}
