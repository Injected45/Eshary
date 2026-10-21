import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/employee_alerts/presentation/employee_alerts_providers.dart';
import 'package:eshary/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('"إعدادات الحوالات" holds the six transfer settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [unreadAlertsCountProvider.overrideWithValue(3)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: TransferSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('إعدادات الحوالات'), findsOneWidget, reason: 'the title');
    for (final t in [
      'شركات الصرافة',
      'حساباتي',
      'العملاء',
      'الفروع',
      'إدارة الموظفين',
      'إشعارات الموظفين',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // the unread alerts are still counted beside "إشعارات الموظفين"
    expect(find.text('3'), findsOneWidget);
  });

  test('the main settings keep the rest, and open the new screen', () {
    final src = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    final main = src.substring(0, src.indexOf('class TransferSettingsScreen'));
    // moved out of the main list
    for (final t in [
      "title: 'شركات الصرافة'",
      "title: 'حساباتي'",
      "title: 'العملاء'",
      "title: 'الفروع'",
      "title: 'إدارة الموظفين'",
      "title: 'إشعارات الموظفين'",
    ]) {
      expect(main.contains(t), isFalse, reason: t);
    }
    // the new entry, with the unread-alerts count on it
    expect(main, contains("title: 'إعدادات الحوالات'"));
    expect(main, contains('badge: ref.watch(unreadAlertsCountProvider)'));
    // everything else stays where it was
    for (final t in [
      "title: 'الملف الشخصي'",
      "title: 'سياسة الخصوصية'",
      "title: 'شروط الاستخدام'",
      "title: 'إدارة الحسابات'",
      "title: 'النسخ الاحتياطي'",
      "title: 'سجل الأخطاء'",
      "title: 'حذف المدخلات'",
    ]) {
      expect(main, contains(t), reason: t);
    }
  });
}
