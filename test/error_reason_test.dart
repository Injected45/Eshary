import 'dart:io';

import 'package:eshary/shared/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// An unknown error is never a bare "unexpected": the reason itself is shown
/// (short) so it can be reported, and the app keeps a log the user can open.
void main() {
  group('the reason under "حدث خطأ غير متوقع"', () {
    test('a server error shows its message and code', () {
      final msg = friendlyError(
        Exception(
          'PostgrestException(message: canceling statement due to statement timeout, code: 57014, details: null, hint: null)',
        ),
      );
      expect(msg, startsWith('حدث خطأ غير متوقع. تم تسجيل الحدث.\n'));
      expect(msg, contains('statement timeout'));
      expect(msg, contains('57014'));
      expect(msg, isNot(contains('details: null')));
    });

    test('a long reason is cut, a wrapper is stripped', () {
      final long = 'x' * 500;
      final reason = compactReason(Exception('PostgrestException(message: $long)'));
      expect(reason.length, lessThanOrEqualTo(141));
      expect(reason, startsWith('xxxx'));
      expect(compactReason(Exception('admin only')), 'admin only');
    });

    test('a missing sign-in function is named, not "unexpected"', () {
      final msg = friendlyError(Exception('NOT_FOUND'));
      expect(msg, contains('member-session'));
      expect(msg, isNot(contains('غير متوقع')));
    });

    test('known errors keep their own Arabic message (no raw text)', () {
      expect(friendlyError(Exception('insufficient_balance')), isNot(contains('insufficient_balance')));
      expect(friendlyError(Exception('cancel_day_passed')), isNot(contains('\n')));
    });
  });

  test('the log is reachable from the settings (admin)', () {
    final src = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    expect(src, contains("title: 'سجل الأخطاء'"));
    expect(src, contains('const LogsScreen()'));
  });

  test('a restore no longer fires the "new operation" alerts', () {
    final sql = File('supabase/migrations/0056_restore_without_alerts.sql')
        .readAsStringSync();
    expect(sql, contains("set_config('eshary.restoring', 'on', true)"));
    expect(
      RegExp(r"current_setting\('eshary\.restoring', true\)").allMatches(sql).length,
      2,
      reason: 'both alert triggers check the flag',
    );
    expect(sql, contains("set_config('eshary.skip_balance_check', 'on', true)"));
  });
}
