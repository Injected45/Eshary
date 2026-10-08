import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which operation types (خروج / دخول) an employee's screens show. The type
/// follows what they may execute or close; own/all only widens whose rows.
void main() {
  test('exit permission shows exits only (Rafe)', () {
    final t = visibleTypesFor([
      'accounts_own',
      'closings_own',
      'transfers_create',
      'view_own',
    ]);
    expect(t.exits, isTrue);
    expect(t.entries, isFalse);
  });

  test('entry permission shows entries only', () {
    final t = visibleTypesFor(['buys_create', 'view_own']);
    expect(t.exits, isFalse);
    expect(t.entries, isTrue);
  });

  test('exit and entry permissions show both', () {
    final t = visibleTypesFor(['transfers_create', 'buys_create', 'view_own']);
    expect(t.exits && t.entries, isTrue);
  });

  test('"all" permissions widen whose rows, not the type', () {
    final t = visibleTypesFor(['transfers_create', 'view_all', 'closings_all']);
    expect(t.exits, isTrue);
    expect(t.entries, isFalse);
  });

  test('a pure viewer (only "all" permissions) sees both types', () {
    for (final key in ['view_all', 'closings_all', 'accounts_all']) {
      final t = visibleTypesFor([key]);
      expect(t.exits && t.entries, isTrue, reason: key);
    }
  });

  test('own-scope permissions without an execute/close permission show nothing',
      () {
    for (final key in ['view_own', 'closings_own', 'accounts_own']) {
      final t = visibleTypesFor([key]);
      expect(t.exits || t.entries, isFalse, reason: key);
    }
  });

  test('an admin (no employee permissions list) sees both', () {
    final t = visibleTypesFor(null);
    expect(t.exits && t.entries, isTrue);
  });
}
