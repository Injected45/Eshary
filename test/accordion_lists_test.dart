import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/admin_repository.dart';
import 'package:eshary/features/admin/presentation/admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AdminUserRow _row(String id, String name) => AdminUserRow.fromJson({
      'user_id': id,
      'email': name,
      'login_email': '$id@x.invalid',
      'status': 'trial',
      'license_type': 'trial',
      'is_admin': false,
      'created_at': '2026-10-01T00:00:00Z',
      'phone': '+21891$id',
    });

/// The same open-one-close-the-others rule the account screen uses, around the
/// real card.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? open;
  final rows = [_row('1111111', 'شركة أ'), _row('2222222', 'شركة ب')];

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          for (final r in rows)
            AdminUserCard(
              row: r,
              isSelf: false,
              expanded: open == r.userId,
              onToggle: () =>
                  setState(() => open = open == r.userId ? null : r.userId),
              onActivateLifetime: () {},
              onDelete: () {},
              onSubscription: (_) {},
            ),
        ],
      );
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: _Harness()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('accounts: only the names show until one is opened',
      (tester) async {
    await pump(tester);
    expect(find.text('شركة أ'), findsOneWidget);
    expect(find.text('شركة ب'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-phone')), findsNothing);
    expect(find.text('فترة تجريبية'), findsNothing);
    expect(find.byType(PopupMenuButton<AdminAction>), findsNothing);
  });

  testWidgets('accounts: opening one closes the other; same tap closes it',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('account-header-1111111')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-phone')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('user-phone'))).data,
      '+218911111111',
    );

    await tester.tap(find.byKey(const ValueKey('account-header-2222222')));
    await tester.pumpAndSettle();
    // still exactly one open, and it is the second
    expect(find.byKey(const ValueKey('user-phone')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('user-phone'))).data,
      '+218912222222',
    );

    // the same header again closes it: nothing open
    await tester.tap(find.byKey(const ValueKey('account-header-2222222')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-phone')), findsNothing);
  });

  test('the account and employee screens keep a single open id', () {
    final admin = File('lib/features/admin/presentation/admin_screen.dart')
        .readAsStringSync();
    expect(admin, contains('String? _openId;'));
    expect(admin, contains('expanded: _openId == rows[i].userId'));

    final emp = File('lib/features/sub_users/presentation/sub_users_screen.dart')
        .readAsStringSync();
    expect(emp, contains('String? _openId;'));
    expect(emp, contains('expanded: _openId == u.id'));
    // the card shows the name in its header, and details only when expanded
    expect(emp, contains('if (expanded) ...['));
    expect(emp, contains("ValueKey('employee-header-"));
  });
}
