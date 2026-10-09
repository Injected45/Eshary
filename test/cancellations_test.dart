import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/cancellations/domain/cancellation.dart';
import 'package:eshary/features/cancellations/presentation/cancel_operation_dialog.dart';
import 'package:eshary/features/cancellations/presentation/cancellations_providers.dart';
import 'package:eshary/features/cancellations/presentation/operation_cancel_bar.dart';
import 'package:eshary/features/companies/domain/account_statement.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/employee_alerts/domain/employee_alert.dart';
import 'package:eshary/features/employee_alerts/presentation/employee_alerts_screen.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/logger.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 10, 8);
DateTime _at(int h, [int m = 0]) => DateTime(2026, 10, 8, h, m);

CurrencyBuy _buy(String id, double usd, DateTime at,
        {DateTime? cancelledAt, String? by,}) =>
    CurrencyBuy(
      id: id,
      ownerId: 'o',
      myCompanyId: 'c1',
      exchangeId: 'e1',
      clientId: null,
      clientFromAccount: 'عميل',
      usdAmount: usd,
      rate: 5,
      lydAmount: usd * 5,
      reference: 'IN-$id',
      status: CurrencyBuyStatus.archived,
      createdAt: at,
      archivedAt: at,
      createdByEmployeeId: by,
      cancelledAt: cancelledAt,
    );

Transfer _out(String id, double amount, DateTime at,
        {DateTime? cancelledAt, String? by,}) =>
    Transfer(
      id: id,
      ownerId: 'o',
      companyId: 'c1',
      exchangeId: 'e1',
      beneficiaryName: 'مستفيد',
      beneficiaryAccountCompany: 'شركة',
      beneficiaryCode: 'B1',
      amount: amount,
      reference: 'A$id',
      status: TransferStatus.archived,
      createdAt: at,
      archivedAt: at,
      createdByEmployeeId: by,
      cancelledAt: cancelledAt,
    );

OperationCancellation _record(int i) => OperationCancellation.fromJson({
      'id': 'c$i',
      'kind': i.isEven ? 'transfer' : 'buy',
      'operation_id': 'op$i',
      'company_name': 'الرحالة الأولى',
      'exchange_name': i.isEven ? 'بهار روز' : 'الليبية الدولية',
      'exchange_code': 'X-1',
      'amount': 100 + i,
      'reference': 'A$i',
      'party_name': 'رافع المهدي',
      'operation_created_at': '2026-10-08T08:00:00Z',
      'operation_employee_name': i.isEven ? 'المدير' : 'سامي',
      'requested_by_name': i.isEven ? null : 'سامي',
      'reason': 'المبلغ مُدخل بالخطأ',
      'balance_before': 1000,
      'balance_after': 1100 + i,
      'cancelled_by_name': 'حسن',
      'cancelled_at': '2026-10-08T09:00:00Z',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the operation keeps its values; only the mark is new', () {
    test('cancelled_at is read from the row', () {
      final t = Transfer.fromJson({
        'id': 't',
        'owner_id': 'o',
        'company_id': 'c',
        'exchange_id': 'e',
        'beneficiary_name': 'x',
        'amount': 300,
        'reference': 'A2',
        'status': 'archived',
        'created_at': '2026-10-08T08:00:00Z',
        'cancelled_at': '2026-10-08T09:00:00Z',
      });
      expect(t.isCancelled, isTrue);
      expect(t.amount, 300);
      expect(t.netAmount, 0);
    });

    test('a live operation counts in full', () {
      expect(_buy('b', 50, _at(9)).netAmount, 50);
      expect(_out('t', 20, _at(9)).netAmount, 20);
      expect(_buy('b', 50, _at(9), cancelledAt: _at(10)).netAmount, 0);
    });
  });

  group('same calendar day only', () {
    test('today: yes', () {
      expect(
        canCancelToday(
          createdAt: _at(8),
          cancelledAt: null,
          now: _at(23, 59),
        ),
        isTrue,
      );
    });

    test('23:59 yesterday is not cancellable at 00:01', () {
      expect(
        canCancelToday(
          createdAt: DateTime(2026, 10, 8, 23, 59),
          cancelledAt: null,
          now: DateTime(2026, 10, 9, 0, 1),
        ),
        isFalse,
      );
    });

    test('already cancelled: no', () {
      expect(
        canCancelToday(createdAt: _at(8), cancelledAt: _at(9), now: _at(10)),
        isFalse,
      );
    });
  });

  group('the answer of admin_cancel_operation', () {
    test('done', () {
      final r = parseCancelResult({'ok': true, 'balance_after': 1500});
      expect(r, isA<CancelDone>());
      expect((r as CancelDone).balanceAfter, 1500);
    });
    test('wrong password, with the tries left', () {
      final r = parseCancelResult(
        {'ok': false, 'error': 'wrong_password', 'remaining': 3},
      );
      expect((r as CancelWrongPassword).remaining, 3);
    });
    test('locked / no password', () {
      expect(
        parseCancelResult({'ok': false, 'error': 'locked'}),
        isA<CancelLocked>(),
      );
      expect(
        parseCancelResult({'ok': false, 'error': 'password_not_set'}),
        isA<CancelPasswordNotSet>(),
      );
    });
  });

  group('refusals read in Arabic', () {
    for (final code in [
      'cancel_day_passed',
      'cancel_already',
      'cancel_insufficient_balance',
      'cancel_reason_required',
      'cancel_request_exists',
      'cancel_request_not_found',
      'cancel_not_found',
    ]) {
      test(code, () {
        final msg = friendlyError(Exception('PostgrestException: $code'));
        expect(msg, isNot(contains(code)));
        expect(RegExp('[؀-ۿ]').hasMatch(msg), isTrue);
      });
    }
    test('a cancelled entry above the balance says why', () {
      expect(
        friendlyError(Exception('cancel_insufficient_balance')),
        contains('رصيد'),
      );
    });
  });

  group('statement: the operation and its reversing entry, both sides', () {
    test('a cancelled entry: دخول 1000 then خروج 1000, balance back', () {
      final s = buildAccountStatement(
        buys: [_buy('b', 1000, _at(9), cancelledAt: _at(10))],
        transfers: [_out('t', 200, _at(11))],
        start: _day,
        end: _at(23, 59),
        openingBalance: 500,
      );
      expect(s.entries.length, 3);
      expect(s.entries[0].income, 1000);
      expect(s.entries[0].cancelled, isTrue);
      expect(s.entries[0].isReversal, isFalse);
      expect(s.entries[1].outgoing, 1000);
      expect(s.entries[1].cancelled, isTrue);
      expect(s.entries[1].isReversal, isTrue);
      expect(s.entries[1].balance, 500);
      expect(s.entries[2].cancelled, isFalse);
      expect(s.balance, 300);
      expect(s.totalIncome, 1000);
      expect(s.totalOutgoing, 1200);
    });

    test('a cancelled exit: خروج then دخول, net zero', () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: [_out('t', 300, _at(9), cancelledAt: _at(9, 5))],
        start: _day,
        end: _at(23, 59),
        openingBalance: 1000,
      );
      expect(s.entries.map((e) => e.balance), [700, 1000]);
      expect(s.entries.every((e) => e.cancelled), isTrue);
      expect(s.balance, 1000);
    });

    test("an employee's statement carries the reversal of their operation", () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: [
          _out('t', 50, _at(9), cancelledAt: _at(9, 30), by: 'emp'),
          _out('u', 70, _at(9), by: 'other'),
        ],
        start: _day,
        end: _at(23, 59),
        scope: StatementScope.employee,
        employeeId: 'emp',
      );
      expect(s.entries.length, 2);
      expect(s.balance, 0);
    });

    test('opening balance stays right after a cancellation', () {
      // Real balance now 1000: +1000 entry cancelled (−1000), −300 exit
      // cancelled (+300) → the account held 1000 at the start of the day.
      final opening = openingBalanceAt(
        currentBalance: 1000,
        buys: [_buy('b', 1000, _at(9), cancelledAt: _at(10))],
        transfers: [_out('t', 300, _at(11), cancelledAt: _at(12))],
        start: _day,
      );
      expect(opening, 1000);
      final s = buildAccountStatement(
        buys: [_buy('b', 1000, _at(9), cancelledAt: _at(10))],
        transfers: [_out('t', 300, _at(11), cancelledAt: _at(12))],
        start: _day,
        end: _at(23, 59),
        openingBalance: opening,
      );
      expect(s.balance, 1000, reason: 'the statement ends on the real balance');
    });
  });

  group('alerts: an employee asks for a cancellation', () {
    EmployeeAlert alert(String kind) => EmployeeAlert.fromJson({
          'id': 'a',
          'sub_user_id': 's',
          'employee_name': 'رافع المهدي',
          'kind': kind,
          'operation_id': 'op',
          'amount': 50,
          'party_name': 'مستفيد',
          'created_at': '2026-10-08T08:00:00Z',
        });

    test('kinds are read', () {
      expect(alert('cancel_request_transfer').kind,
          AlertKind.cancelRequestTransfer,);
      expect(alert('cancel_request_buy').kind, AlertKind.cancelRequestBuy);
      expect(alert('cancel_request_transfer').isExit, isTrue);
      expect(alert('cancel_request_buy').isExit, isFalse);
    });

    test('the notification text says it is a request', () {
      final text = alertText(alert('cancel_request_transfer'));
      expect(text, startsWith('طلب إلغاء "خروج" من الموظف رافع المهدي'));
      expect(text, contains('50.00'));
      expect(alertText(alert('transfer')), startsWith('تم تنفيذ "خروج"'));
    });
  });

  group('PDF', () {
    test('كشف الإلغاءات builds with 0, 1 and 80 rows', () async {
      final pdf = await PdfExport.load();
      for (final n in [0, 1, 80]) {
        final bytes = await pdf.buildCancellationsReport(
          rows: [for (var i = 0; i < n; i++) _record(i)],
          start: _day,
          end: _at(23, 59),
          exportedBy: 'حسن',
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: '$n');
      }
    });

    test('the movement and kind reports build with cancelled rows', () async {
      final pdf = await PdfExport.load();
      final buys = [
        _buy('b', 1000, _at(9), cancelledAt: _at(10)),
        _buy('c', 40, _at(11)),
      ];
      final transfers = [_out('t', 300, _at(12), cancelledAt: _at(12, 5))];
      for (final bytes in [
        await pdf.buildDetailedTransfersReport(
          buys: buys,
          transfers: transfers,
          companyById: const {},
          exchangeById: const {},
          clientById: const {},
          start: _day,
          end: _at(23, 59),
        ),
        await pdf.buildIncomeDetailsReport(
          buys: buys,
          companyById: const {},
          exchangeById: const {},
          clientById: const {},
          start: _day,
          end: _at(23, 59),
        ),
        await pdf.buildOutgoingDetailsReport(
          transfers: transfers,
          companyById: const {},
          exchangeById: const {},
          start: _day,
          end: _at(23, 59),
        ),
      ]) {
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });

    test('purple for both sides, and cancelled rows left out of kind totals', () {
      final src = File('lib/shared/pdf_export_period.dart').readAsStringSync();
      expect(src, contains('const _cancelledColor = PdfColors.purple700;'));
      expect(src, contains('op.reversalAt('));
      expect(src, contains(".where((r) => !r.cancelled)"));
    });
  });

  group('the details page', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool employee,
      DateTime? createdAt,
      DateTime? cancelledAt,
      List<CancellationRequest> requests = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isEmployeeProvider.overrideWithValue(employee),
            cancelRequestsProvider.overrideWith((ref) async => requests),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: OperationCancelBar(
                  kind: OperationKind.transfer,
                  operationId: 'op',
                  amount: 50,
                  createdAt: createdAt ?? DateTime.now(),
                  cancelledAt: cancelledAt,
                  partyName: 'مستفيد',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('admin, today: إلغاء العملية', (tester) async {
      await pump(tester, employee: false);
      expect(find.text('إلغاء العملية'), findsOneWidget);
      expect(find.text('طلب إلغاء العملية'), findsNothing);
    });

    testWidgets('employee, today: طلب إلغاء العملية', (tester) async {
      await pump(tester, employee: true);
      expect(find.text('طلب إلغاء العملية'), findsOneWidget);
      expect(find.text('إلغاء العملية'), findsNothing);
    });

    testWidgets('an earlier day: no button at all', (tester) async {
      await pump(
        tester,
        employee: false,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('cancelled: the purple banner, no button', (tester) async {
      await pump(tester, employee: false, cancelledAt: DateTime.now());
      expect(find.textContaining('عملية ملغاة'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('employee with a request sent: waiting, no second request',
        (tester) async {
      await pump(
        tester,
        employee: true,
        requests: [
          CancellationRequest.fromJson({
            'id': 'r',
            'sub_user_id': 's',
            'employee_name': 'رافع',
            'kind': 'transfer',
            'operation_id': 'op',
            'amount': 50,
            'reason': 'خطأ',
            'status': 'pending',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ],
      );
      expect(find.textContaining('بانتظار المدير'), findsOneWidget);
      expect(find.text('طلب إلغاء العملية'), findsNothing);
    });

    testWidgets('admin sees the employee request on the operation',
        (tester) async {
      await pump(
        tester,
        employee: false,
        requests: [
          CancellationRequest.fromJson({
            'id': 'r',
            'sub_user_id': 's',
            'employee_name': 'رافع',
            'kind': 'transfer',
            'operation_id': 'op',
            'amount': 50,
            'reason': 'المستفيد خطأ',
            'status': 'pending',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ],
      );
      expect(find.textContaining('طلب إلغاء من الموظف رافع'), findsOneWidget);
      expect(find.text('الموافقة وإلغاء العملية'), findsOneWidget);
    });
  });

  group('the dialog', () {
    Future<void> open(WidgetTester tester, {required bool employee}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CancelOperationDialog(
                  kind: OperationKind.buy,
                  operationId: 'op',
                  amount: 1000,
                  asEmployee: employee,
                  partyName: 'عميل',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('admin: reason and password', (tester) async {
      await open(tester, employee: false);
      expect(find.text('سبب الإلغاء'), findsOneWidget);
      expect(find.text('كلمة مرور حسابك'), findsOneWidget);
      expect(find.text('تأكيد الإلغاء'), findsOneWidget);
    });

    testWidgets('admin: nothing is sent without a reason / password',
        (tester) async {
      await open(tester, employee: false);
      await tester.tap(find.text('تأكيد الإلغاء'));
      await tester.pumpAndSettle();
      expect(find.textContaining('اكتب سبب الإلغاء'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'إدخال خاطئ');
      await tester.tap(find.text('تأكيد الإلغاء'));
      await tester.pumpAndSettle();
      expect(find.textContaining('كلمة مرور حسابك لتأكيد'), findsOneWidget);
    });

    testWidgets('the password is hidden', (tester) async {
      await open(tester, employee: false);
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.obscureText, isTrue);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('employee: a request, no password field', (tester) async {
      await open(tester, employee: true);
      expect(find.text('كلمة مرور حسابك'), findsNothing);
      expect(find.text('إرسال الطلب'), findsOneWidget);
    });
  });

  group('wiring', () {
    test('every place that totals operations leaves cancelled ones out', () {
      for (final f in [
        'lib/features/archive/presentation/archive_providers.dart',
        'lib/features/archive/presentation/archive_screen.dart',
        'lib/features/archive/presentation/history_details_screen.dart',
        'lib/features/archive/presentation/employees_operations_screen.dart',
        'lib/features/employee_auth/presentation/employee_records_screen.dart',
        'lib/features/transfers/presentation/transfers_screen.dart',
        'lib/features/currency_buy/presentation/currency_buy_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('netAmount'), reason: f);
      }
    });

    test('the details page carries the cancel bar for both kinds', () {
      final src = File('lib/shared/transaction_details.dart').readAsStringSync();
      expect('OperationCancelBar('.allMatches(src).length, 2);
    });

    test('the migration closes direct writes and keeps the record append-only',
        () {
      final sql =
          File('supabase/migrations/0048_cancellations.sql').readAsStringSync();
      expect(sql, contains('drop policy if exists transfers_delete_own'));
      expect(sql, contains('drop policy if exists currency_buys_update_own'));
      expect(sql, contains(
          'revoke insert, update, delete on operation_cancellations from authenticated',),);
      expect(sql, contains("at time zone 'Africa/Tripoli'"));
      expect(sql, contains('crypt(p_password, v_hash)'));
    });
  });
}
