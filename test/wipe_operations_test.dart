import 'dart:io';

import 'package:eshary/features/settings/data/wipe_repository.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the settings screen no longer deletes row by row', () {
    final src = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    // that produced "حُذفت جزئيًا. أخطاء: 2" once the API refused direct deletes
    expect(src, isNot(contains('حُذفت جزئيًا')));
    expect(src, isNot(contains(".from(table).delete()")));
    // since 0087 the wipe asks for the administrator's password
    expect(src, contains('wipeOperations(password)'));
    expect(src, contains('تم حذف كل العمليات المالية'));
  });

  test('a refused wipe (the password) deleted nothing and says why', () {
    final r = WipeResult.fromJson(
      {'ok': false, 'error': 'wrong_password', 'remaining': 3},
    );
    expect(r.ok, isFalse);
    expect(r.error, 'wrong_password');
    expect(r.remaining, 3);
    expect(WipeResult.fromJson({'ok': true, 'transfers': 1}).ok, isTrue);
  });

  test(
      '0087: the password, everything that depends on the operations, and '
      'the numbering goes on', () {
    final sql = File('supabase/migrations/0087_operations_integrity.sql')
        .readAsStringSync();
    expect(sql, contains('owner_wipe_operations(p_password text)'));
    expect(sql, contains('_admin_password_error(v_owner, p_password)'));
    for (final t in [
      'lyd_treasury',
      'lyd_movements',
      'lyd_counts',
      'operation_costs',
      'account_cost_events',
      'account_costs',
      'balance_adjustments',
    ]) {
      expect(sql, contains('delete from $t where owner_id = v_owner'),
          reason: t);
    }
    expect(sql, contains('set start_ref = next_reference(r.id)'));
  });

  test('the answer of the database is read', () {
    final r = WipeResult.fromJson({
      'transfers': 3,
      'currency_buys': 2,
      'cancellations': 1,
    });
    expect(r.transfers, 3);
    expect(r.currencyBuys, 2);
    expect(r.total, 5);
  });

  test('the migration wipes everything in one step, after a safety backup', () {
    final sql =
        File('supabase/migrations/0054_wipe_operations.sql').readAsStringSync();
    expect(sql, contains("_save_backup('pre_wipe')"));
    expect(sql, contains('delete from transfers where owner_id = v_owner'));
    expect(sql, contains('delete from currency_buys where owner_id = v_owner'));
    expect(sql, contains('delete from operation_cancellations'));
    expect(sql, contains('current_employee_id() is not null'));
    expect(
        sql,
        contains(
            'grant execute on function owner_wipe_operations() to authenticated'));
  });

  test('"not_authorized" reads in Arabic', () {
    final msg = friendlyError(Exception('PostgrestException: not_authorized'));
    expect(msg, isNot(contains('not_authorized')));
  });
}
