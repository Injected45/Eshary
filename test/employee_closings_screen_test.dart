import 'package:eshary/features/archive/presentation/archive_screen.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buys_providers.dart';
import 'package:eshary/features/employee_auth/data/employee_auth_repository.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EmployeeIdentity _employee(List<String> permissions) => EmployeeIdentity(
      sessionId: 's',
      subUserId: 'u',
      parentAdminId: 'a',
      employeeName: 'رافع',
      permissions: permissions,
      branchId: null,
    );

/// Opens the closings tab as [identity] (null = admin) and returns the text
/// of everything on screen.
Future<void> _open(WidgetTester tester, EmployeeIdentity? identity) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentEmployeeProvider.overrideWith((ref) async => identity),
        archivedBuysProvider
            .overrideWith((ref) async => const <CurrencyBuy>[]),
        archivedTransfersProvider
            .overrideWith((ref) async => const <Transfer>[]),
      ],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: ArchiveScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'exits-only employee (Rafe): closings show exits only, no entry anywhere',
    (tester) async {
      await _open(
        tester,
        _employee([
          'accounts_own',
          'archive_transfers',
          'closings_own',
          'transfers_create',
          'view_own',
        ]),
      );
      expect(find.textContaining('إجمالي الخروج'), findsOneWidget);
      expect(find.textContaining('إجمالي الدخول'), findsNothing);
      expect(find.textContaining('فرق الحركة'), findsNothing);
      expect(find.textContaining('تفاصيل الدخول'), findsNothing);
      expect(find.textContaining('تفاصيل الخروج'), findsOneWidget);
    },
  );

  testWidgets('entries-only employee: entries only, no exit anywhere',
      (tester) async {
    await _open(tester, _employee(['buys_create', 'closings_own']));
    expect(find.textContaining('إجمالي الدخول'), findsOneWidget);
    expect(find.textContaining('إجمالي الخروج'), findsNothing);
    expect(find.textContaining('فرق الحركة'), findsNothing);
    expect(find.textContaining('تفاصيل الخروج'), findsNothing);
  });

  testWidgets('full closings permission and the admin see both types',
      (tester) async {
    for (final id in [_employee(['closings_all']), null]) {
      await _open(tester, id);
      expect(find.textContaining('إجمالي الدخول'), findsOneWidget);
      expect(find.textContaining('إجمالي الخروج'), findsOneWidget);
      expect(find.textContaining('فرق الحركة'), findsOneWidget);
    }
  });
}
