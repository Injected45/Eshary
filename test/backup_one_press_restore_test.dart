import 'package:eshary/core/theme.dart';
import 'package:eshary/features/admin/data/backup_repository.dart';
import 'package:eshary/features/admin/presentation/backup_screen.dart';
import 'package:eshary/shared/cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackups implements BackupRepository {
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> get(String id) async {
    calls.add('get:$id');
    return {'app': 'eshary', 'tables': <String, dynamic>{}, 'id': id};
  }

  @override
  Future<Map<String, dynamic>> restore(Map<String, dynamic> backup) async {
    calls.add('restore:${backup['id']}');
    return {};
  }

  @override
  Future<List<BackupOwner>> owners(String id) async {
    calls.add('owners:$id');
    return const [
      BackupOwner(
        ownerId: 'o1',
        name: 'الرحالة',
        email: 'a@x.ly',
        exists: true,
        transfers: 12,
        currencyBuys: 4,
      ),
      BackupOwner(
        ownerId: 'o2',
        name: 'محذوف',
        email: null,
        exists: false,
        transfers: 1,
        currencyBuys: 0,
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> restoreOwner(String id, String ownerId) async {
    calls.add('restoreOwner:$id:$ownerId');
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _t = DateTime.utc(2026, 10, 10, 8, 30);

Future<_FakeBackups> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final fake = _FakeBackups();
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        backupRepositoryProvider.overrideWithValue(fake),
        backupsListProvider.overrideWith(
          (ref) async => [
            BackupInfo(
                id: 'b2', kind: 'manual', createdAt: _t, sizeBytes: 2048),
            BackupInfo(
              id: 'b1',
              kind: 'auto',
              createdAt: _t.subtract(const Duration(days: 1)),
              sizeBytes: 1024,
            ),
          ],
        ),
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
  return fake;
}

void main() {
  testWidgets('every saved backup has a labelled "استعادة" button',
      (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('backup-restore-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-restore-b2')), findsOneWidget);
    expect(find.text('استعادة'), findsNWidgets(2));
  });

  // Since 0088 the one question is WHO goes back: one subscriber, or every
  // subscriber (a full restore takes everyone back and loses what they did
  // since). After that choice: no confirmation, as before.
  testWidgets('the whole platform: the choice, then at once, no more questions',
      (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b1')));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty, reason: 'nothing before the choice');
    await tester.tap(find.byKey(const ValueKey('restore-scope-all')));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد نهائي'), findsNothing);
    // the stored backup was fetched and applied, in that order, exactly once
    expect(fake.calls, ['get:b1', 'restore:b1']);
    expect(find.textContaining('عاد التطبيق كله إلى نسخة'), findsOneWidget);
    expect(find.textContaining('نسخة أمان'), findsWidgets);
  });

  testWidgets('each backup restores its own data', (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-scope-all')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['get:b2', 'restore:b2']);
  });

  testWidgets('one subscriber: only that one goes back', (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-scope-one')));
    await tester.pumpAndSettle();
    expect(find.text('الرحالة'), findsOneWidget);
    expect(find.textContaining('12 بيع · 4 شراء'), findsOneWidget);
    // a deleted account is shown but cannot be chosen
    await tester.tap(find.byKey(const ValueKey('restore-owner-o2')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['owners:b2']);
    await tester.tap(find.byKey(const ValueKey('restore-owner-o1')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['owners:b2', 'restoreOwner:b2:o1']);
    expect(find.textContaining('عاد الرحالة إلى نسخة'), findsOneWidget);
  });

  testWidgets('cancelling the choice restores nothing', (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
  });
}
