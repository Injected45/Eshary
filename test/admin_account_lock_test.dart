import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/admin_repository.dart';
import 'package:eshary/features/admin/presentation/admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AdminUserRow _row({required bool admin, String status = 'active'}) =>
    AdminUserRow.fromJson({
      'user_id': 'u',
      'email': 'a@gmail.com',
      'status': status,
      'license_type': 'lifetime',
      'is_admin': admin,
      'created_at': '2026-10-01T00:00:00Z',
      'phone': '0912345678',
    });

void main() {
  Future<void> show(WidgetTester tester, AdminUserRow row, {bool self = false}) async {
    void noop() {}
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AdminUserCard(
              row: row,
              isSelf: self,
              onActivateTrial: noop,
              onActivateLifetime: noop,
              onBlock: noop,
              onSetPending: noop,
              onGrantAdmin: noop,
              onRevokeAdmin: noop,
              onDelete: noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an administrator account has no menu at all', (tester) async {
    await show(tester, _row(admin: true), self: true);
    expect(find.byType(PopupMenuButton<AdminAction>), findsNothing);
    expect(find.byKey(const ValueKey('admin-locked')), findsOneWidget);
    expect(find.text('مشرف'), findsOneWidget);
  });

  testWidgets('another administrator is locked the same way', (tester) async {
    await show(tester, _row(admin: true));
    expect(find.byType(PopupMenuButton<AdminAction>), findsNothing);
  });

  testWidgets('a normal account keeps its menu, with the delete option',
      (tester) async {
    await show(tester, _row(admin: false, status: 'pending'));
    expect(find.byType(PopupMenuButton<AdminAction>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<AdminAction>));
    await tester.pumpAndSettle();
    for (final t in ['تفعيل تجريبي 3 أيام', 'تفعيل دائم', 'حذف الحساب', 'حظر']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  test('the database refuses to change an administrator licence', () {
    final sql = File('supabase/migrations/0055_protect_admin_license.sql')
        .readAsStringSync();
    expect(sql, contains("raise exception 'admin_license_locked'"));
    expect(sql, contains('before update or delete on account_licenses'));
    expect(sql, contains('auth.uid() is null')); // Dashboard SQL stays free
  });
}
