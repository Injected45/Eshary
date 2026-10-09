import 'dart:io';

import 'package:eshary/features/settings/data/wipe_repository.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the settings screen no longer deletes row by row', () {
    final src =
        File('lib/features/settings/presentation/settings_screen.dart')
            .readAsStringSync();
    // that produced "حُذفت جزئيًا. أخطاء: 2" once the API refused direct deletes
    expect(src, isNot(contains('حُذفت جزئيًا')));
    expect(src, isNot(contains(".from(table).delete()")));
    expect(src, contains('wipeOperations()'));
    expect(src, contains('تم حذف كل العمليات المالية'));
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
    expect(sql, contains('grant execute on function owner_wipe_operations() to authenticated'));
  });

  test('"not_authorized" reads in Arabic', () {
    final msg = friendlyError(Exception('PostgrestException: not_authorized'));
    expect(msg, isNot(contains('not_authorized')));
  });
}
