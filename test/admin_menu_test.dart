import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/admin_repository.dart';
import 'package:eshary/features/admin/presentation/admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AdminUserRow _row(String status) => AdminUserRow.fromJson({
      'user_id': 'u',
      'email': 'شركة — مدير',
      'login_email': 't1@subscribers.eshary.invalid',
      'status': status,
      'license_type': 'trial',
      'is_admin': false,
      'created_at': '2026-10-01T00:00:00Z',
      'phone': '+218912345678',
    });

Future<void> _open(WidgetTester tester, AdminUserRow row) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AdminUserCard(
            row: row,
            isSelf: false,
            onActivateLifetime: () {},
            onDelete: () {},
            onSubscription: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PopupMenuButton<AdminAction>));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the account menu has only the essential actions',
      (tester) async {
    await _open(tester, _row('trial'));
    expect(find.byType(PopupMenuItem<AdminAction>), findsNWidgets(5));
    for (final t in [
      'تمديد التجربة',
      'تأكيد دفع اشتراك',
      'تفعيل دائم',
      'إيقاف الحساب',
      'حذف الحساب',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // the removed ones
    for (final t in [
      'تفعيل تجريبي 3 أيام',
      'إعادة لبانتظار التفعيل',
      'تعيين كمشرف',
      'حظر',
      'إعادة التفعيل',
    ]) {
      expect(find.text(t), findsNothing, reason: t);
    }
  });

  testWidgets('a suspended account offers resuming, not suspending',
      (tester) async {
    await _open(tester, _row('blocked'));
    expect(find.text('إعادة التفعيل'), findsOneWidget);
    expect(find.text('إيقاف الحساب'), findsNothing);
    expect(find.byType(PopupMenuItem<AdminAction>), findsNWidgets(5));
  });

  test('the actions use the real sign-in address, not the display name', () {
    final r = _row('trial');
    expect(r.email, 'شركة — مدير');
    expect(r.loginEmail, 't1@subscribers.eshary.invalid');
  });
}
