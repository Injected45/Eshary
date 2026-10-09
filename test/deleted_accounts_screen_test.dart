import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/admin_repository.dart';
import 'package:eshary/features/admin/domain/deleted_account.dart';
import 'package:eshary/features/admin/presentation/deleted_accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DeletedAccount _d(String email, String? phone, {int companies = 0}) =>
    DeletedAccount.fromJson({
      'id': email,
      'email': email,
      'phone': phone,
      'license_status': 'pending',
      'account_created': '2026-10-01T10:00:00Z',
      'companies': companies,
      'clients': 0,
      'employees': 0,
      'deleted_by_email': 'admin@x.ly',
      'deleted_at': '2026-10-10T09:00:00Z',
    });

void main() {
  Future<void> open(WidgetTester tester, List<DeletedAccount> rows) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deletedAccountsProvider.overrideWith((ref) async => rows)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: DeletedAccountsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows e-mail, phone, who deleted it and what went with it',
      (tester) async {
    await open(tester, [_d('a@gmail.com', '0912345678', companies: 2)]);
    expect(find.textContaining('a@gmail.com'), findsOneWidget);
    expect(find.text('0912345678'), findsOneWidget);
    expect(find.text('admin@x.ly'), findsOneWidget);
    expect(find.text('2 شركة'), findsOneWidget);
    expect(find.text('بانتظار التفعيل'), findsOneWidget);
  });

  testWidgets('empty log says so', (tester) async {
    await open(tester, const []);
    expect(find.text('لم يُحذف أي حساب بعد.'), findsOneWidget);
  });

  testWidgets('search by e-mail or by phone', (tester) async {
    await open(tester, [
      _d('first@gmail.com', '0911111111'),
      _d('second@gmail.com', '0922222222'),
    ]);
    await tester.enterText(find.byType(TextField), '0922');
    await tester.pump();
    expect(find.textContaining('second@gmail.com'), findsOneWidget);
    expect(find.textContaining('first@gmail.com'), findsNothing);
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    expect(find.textContaining('first@gmail.com'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump();
    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });

  test('reachable from the accounts screen, read-only on the server', () {
    final src = File('lib/features/admin/presentation/admin_screen.dart')
        .readAsStringSync();
    expect(src, contains("ValueKey('deleted-accounts-log')"));
    expect(src, contains('DeletedAccountsScreen()'));
    final sql = File('supabase/migrations/0053_deleted_accounts_list.sql')
        .readAsStringSync();
    expect(sql, contains('is_caller_admin()'));
    expect(sql, isNot(contains('to anon')));
  });
}
