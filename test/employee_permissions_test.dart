import 'dart:io';

import 'package:eshary/features/sub_users/domain/employee_permissions.dart';
import 'package:eshary/features/sub_users/domain/sub_user.dart';
import 'package:eshary/features/sub_users/presentation/employee_permissions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SubUser _user(List<String> permissions) => SubUser(
      id: 'u1',
      parentAdminId: 'a1',
      employeeName: 'سامي',
      phoneNumber: '0911110000',
      loginCodeUsed: true,
      permissions: permissions,
      status: SubUserStatus.active,
      deviceId: null,
      branchId: null,
      lastLoginAt: null,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('permission list', () {
    test('keys are unique and labelled', () {
      final keys = kEmployeePermissions.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final p in kEmployeePermissions) {
        expect(p.label.trim(), isNotEmpty);
        expect(p.description.trim(), isNotEmpty);
      }
    });

    test('matches the keys the database accepts (migration 0043)', () {
      final sql =
          File('supabase/migrations/0044_scoped_close.sql').readAsStringSync();
      final body = RegExp(
        r"_employee_permission_keys\(\)[\s\S]*?select array\[([\s\S]*?)\]",
      ).firstMatch(sql)!.group(1)!;
      final dbKeys = RegExp(r"'([a-z_]+)'")
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expect(kEmployeePermissions.map((p) => p.key).toSet(), dbKeys);
    });

    test('a new SubUser parses with no permissions', () {
      final u = SubUser.fromJson({
        'id': 'x',
        'parent_admin_id': 'a',
        'employee_name': 'n',
        'phone_number': '0911110000',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(u.permissions, isEmpty);
    });

    test('permissions are read from the row', () {
      final u = SubUser.fromJson({
        'id': 'x',
        'parent_admin_id': 'a',
        'employee_name': 'n',
        'phone_number': '0911110000',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00Z',
        'permissions': ['transfers_create', 'view_own'],
      });
      expect(u.permissions, ['transfers_create', 'view_own']);
    });
  });

  group('permissions dialog', () {
    testWidgets('starts empty for a new employee and saves only after a change',
        (t) async {
      await t.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmployeePermissionsDialog(user: _user(const [])),
            ),
          ),
        ),
      );

      expect(find.byType(SwitchListTile), findsNWidgets(kEmployeePermissions.length));
      final switches = t.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      expect(switches.every((s) => !s.value), isTrue);

      FilledButton save() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'حفظ'));
      expect(save().onPressed, isNull, reason: 'nothing changed yet');

      await t.tap(find.byType(SwitchListTile).first);
      await t.pump();
      expect(save().onPressed, isNotNull);

      await t.tap(find.byType(SwitchListTile).first);
      await t.pump();
      expect(save().onPressed, isNull, reason: 'back to the original state');
    });

    testWidgets('shows the permissions already granted', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmployeePermissionsDialog(
                user: _user(const [kPermTransfersCreate, kPermViewOwn]),
              ),
            ),
          ),
        ),
      );
      final on = t
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .where((s) => s.value)
          .length;
      expect(on, 2);
    });
  });
}
