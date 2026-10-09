import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/backup_repository.dart';
import 'package:eshary/features/admin/presentation/backup_screen.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements BackupRepository {
  final deleted = <List<String>>[];

  @override
  Future<int> deleteMany(List<String> ids) async {
    deleted.add(ids);
    return ids.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BackupInfo _b(String id, String kind, int daysAgo) => BackupInfo(
      id: id,
      kind: kind,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      sizeBytes: 2 * 1024 * 1024,
    );

void main() {
  Future<_Repo> open(WidgetTester tester, List<BackupInfo> rows) async {
    final repo = _Repo();
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupRepositoryProvider.overrideWithValue(repo),
          backupsListProvider.overrideWith((ref) async => rows),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: BackupScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  final rows = [
    _b('a', 'auto', 0),
    _b('b', 'auto', 10),
    _b('c', 'manual', 20),
  ];

  testWidgets('says the backup is every 24 hours, kept 30 days', (tester) async {
    await open(tester, rows);
    expect(find.textContaining('كل 24 ساعة'), findsOneWidget);
    expect(find.textContaining('30 يوماً'), findsOneWidget);
    expect(find.textContaining('كل ساعة'), findsNothing);
  });

  testWidgets('nothing is deleted until something is ticked', (tester) async {
    await open(tester, rows);
    final del = find.byKey(const ValueKey('backup-delete'));
    expect(tester.widget<FilledButton>(del).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('backup-check-b')));
    await tester.pump();
    expect(tester.widget<FilledButton>(del).onPressed, isNotNull);
    expect(find.text('حذف المحدد (1)'), findsOneWidget);
  });

  testWidgets('tick two, confirm, and exactly those two are deleted',
      (tester) async {
    final repo = await open(tester, rows);
    await tester.tap(find.byKey(const ValueKey('backup-check-b')));
    await tester.tap(find.byKey(const ValueKey('backup-check-c')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-delete')));
    await tester.pumpAndSettle();
    expect(find.text('حذف 2 نسخة؟'), findsOneWidget);
    expect(repo.deleted, isEmpty, reason: 'not before the confirmation');
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(repo.deleted.single.toSet(), {'b', 'c'});
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    final repo = await open(tester, rows);
    await tester.tap(find.byKey(const ValueKey('backup-check-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
  });

  testWidgets('select all / clear', (tester) async {
    await open(tester, rows);
    await tester.tap(find.byKey(const ValueKey('backup-select-all')));
    await tester.pump();
    expect(find.text('حذف المحدد (3)'), findsOneWidget);
    expect(find.text('إلغاء التحديد'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('backup-select-all')));
    await tester.pump();
    expect(find.text('حذف المحدد (3)'), findsNothing);
  });

  group('account deletion', () {
    test('the card offers the deletion, never for yourself or an admin', () {
      final src = File('lib/features/admin/presentation/admin_screen.dart')
          .readAsStringSync();
      expect(src, contains('_AdminAction.delete'));
      expect(src, contains("'حذف الحساب'"));
      expect(src, contains('.deleteUser(rows[i].userId)'));
      // shown only inside the same condition as الحظر
      final at = src.indexOf('value: _AdminAction.delete');
      expect(src.lastIndexOf('if (!isSelf && !row.isAdmin)', at), greaterThan(0));
      // the confirmation shows the e-mail and the phone
      expect(src, contains("'البريد: \${rows[i].email}"));
      expect(src, contains("'الهاتف: "));
    });

    test('the database refuses what it should, in Arabic', () {
      for (final code in [
        'user_has_operations',
        'cannot_delete_self',
        'cannot_delete_admin',
        'user_not_found',
        'keep_one_backup',
      ]) {
        final msg = friendlyError(Exception('PostgrestException: $code'));
        expect(msg, isNot(contains(code)));
        expect(RegExp('[؀-ۿ]').hasMatch(msg), isTrue, reason: code);
      }
    });

    test('the migration: daily at 00:00 Libya, 30 days, last backup protected',
        () {
      final sql =
          File('supabase/migrations/0052_delete_accounts_and_daily_backups.sql')
              .readAsStringSync();
      expect(sql, contains("'0 22 * * *'"));
      expect(sql, contains("interval '30 days'"));
      expect(sql, contains("raise exception 'keep_one_backup'"));
      expect(sql, contains("raise exception 'user_has_operations'"));
      expect(sql, contains('cron.unschedule'));
    });
  });
}
