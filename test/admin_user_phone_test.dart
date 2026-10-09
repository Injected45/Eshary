import 'dart:io';

import 'package:eshary/features/admin/domain/admin_user_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> json({String? phone}) => {
        'user_id': 'u',
        'email': 'a@gmail.com',
        'status': 'pending',
        'is_admin': false,
        'created_at': '2026-10-10T00:00:00Z',
        'phone': phone,
      };

  test('the users list carries the confirmed phone', () {
    expect(AdminUserRow.fromJson(json(phone: '0912345678')).phone, '0912345678');
    expect(AdminUserRow.fromJson(json()).phone, isNull);
  });

  test('an older server answer without the column still reads', () {
    final j = json()..remove('phone');
    expect(AdminUserRow.fromJson(j).phone, isNull);
  });

  test('the card shows the phone and the search finds it', () {
    final src =
        File('lib/features/admin/presentation/admin_screen.dart').readAsStringSync();
    expect(src, contains("ValueKey('user-phone')"));
    expect(src, contains("(r.phone ?? '').contains(query)"));
    final sql =
        File('supabase/migrations/0051_admin_list_users_phone.sql').readAsStringSync();
    expect(sql, contains('left join member_phones mp on mp.user_id = u.id'));
    expect(sql, contains('is_caller_admin()'));
  });
}
