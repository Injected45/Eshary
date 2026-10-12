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

  testWidgets('one press restores that backup at once, no questions asked',
      (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b1')));
    await tester.pumpAndSettle();
    // no confirmation dialog in between
    expect(find.text('استعادة نسخة احتياطية؟'), findsNothing);
    expect(find.text('تأكيد نهائي'), findsNothing);
    // the stored backup was fetched and applied, in that order, exactly once
    expect(fake.calls, ['get:b1', 'restore:b1']);
    // and the user is told what happened
    expect(find.textContaining('عاد التطبيق إلى نسخة'), findsOneWidget);
    expect(find.textContaining('نسخة أمان'), findsWidgets);
  });

  testWidgets('each backup restores its own data', (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore-b2')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['get:b2', 'restore:b2']);
  });
}
