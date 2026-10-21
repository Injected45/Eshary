import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/cancellations/domain/cancellation.dart';
import 'package:eshary/features/companies/domain/account_statement.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/expenses/data/account_expenses_repository.dart';
import 'package:eshary/features/expenses/domain/account_expense.dart';
import 'package:eshary/features/expenses/presentation/account_expense_dialog.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccountExpense _x(
  String id,
  double amount,
  DateTime at, {
  String ex = 'e1',
  String? code,
  String note = 'عمولة إدارة الحساب',
  DateTime? cancelledAt,
}) =>
    AccountExpense(
      id: id,
      exchangeId: ex,
      amount: amount,
      code: code,
      note: note,
      createdAt: at,
      createdByName: 'المدير',
      cancelledAt: cancelledAt,
      cancelReason: cancelledAt == null ? null : 'خطأ',
    );

class _FakeRepo implements AccountExpensesRepository {
  final recorded = <Map<String, Object?>>[];
  final cancelled = <String>[];
  CancelResult cancelResult = const CancelDone(0);

  @override
  Future<AccountExpense> record({
    required String exchangeId,
    required double amount,
    String? code,
    required String note,
  }) async {
    recorded.add({
      'exchange': exchangeId,
      'amount': amount,
      'code': code,
      'note': note,
    });
    return _x('new', amount, DateTime.now(), ex: exchangeId, code: code);
  }

  @override
  Future<CancelResult> cancel(
    String id, {
    required String reason,
    required String password,
  }) async {
    cancelled.add('$id|$reason|$password');
    return cancelResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _exchange = Exchange(
  id: 'e1',
  companyId: 'c1',
  name: 'بهار روز',
  balance: 1000,
  ourCode: 'X-1',
  country: null,
  createdAt: DateTime(2026, 1, 1),
);

Future<_FakeRepo> _open(
  WidgetTester tester, {
  List<AccountExpense> today = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountExpensesRepositoryProvider.overrideWithValue(fake),
        allExchangesProvider.overrideWith((ref) async => [_exchange]),
        todayExpensesProvider.overrideWith((ref) async => today),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AccountExpenseDialog(
              exchange: _exchange,
              accountName: 'الرحالة — بهار روز',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Finder _f(String key) => find.byKey(ValueKey(key));

void main() {
  final day = DateTime(2026, 10, 20);
  DateTime at(int h) => DateTime(2026, 10, 20, h);
  final start = DateTime(2026, 10, 20);
  final end = DateTime(2026, 10, 20, 23, 59);

  group('the record', () {
    test('it reads the row and labels itself with its code and its note', () {
      final e = AccountExpense.fromJson({
        'id': 'x1',
        'exchange_id': 'e1',
        'amount': 35.5,
        'code': 'C-77',
        'note': 'عمولة شهر 10',
        'created_at': '2026-10-20T09:00:00Z',
        'created_by_name': 'المدير',
        'cancelled_at': null,
        'cancel_reason': null,
      });
      expect(e.amount, 35.5);
      expect(e.label, 'كود C-77 · عمولة شهر 10');
      expect(e.netAmount, 35.5);
      expect(_x('y', 10, day).label, 'عمولة إدارة الحساب',
          reason: 'no code: the note alone');
      expect(_x('z', 10, day, cancelledAt: day).netAmount, 0,
          reason: 'a cancelled one counts for nothing');
    });
  });

  group('in the account statement', () {
    test('a commission is an exit line with what it is for', () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: const [],
        expenses: [_x('x1', 35.5, at(10), code: 'C-77')],
        start: start,
        end: end,
        openingBalance: 1000,
      );
      expect(s.entries.length, 1);
      final e = s.entries.single;
      expect(e.outgoing, 35.5);
      expect(e.income, isNull);
      expect(e.isExpense, isTrue);
      expect(e.note, 'كود C-77 · عمولة إدارة الحساب');
      expect(e.balance, 964.5, reason: 'the running balance drops');
      expect(s.totalOutgoing, 35.5);
      expect(s.balance, 964.5);
    });

    test('a cancelled commission is netted by its reversing line', () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: const [],
        expenses: [_x('x1', 35.5, at(10), cancelledAt: at(11))],
        start: start,
        end: end,
        openingBalance: 1000,
      );
      expect(s.entries.length, 2);
      expect(s.entries[0].cancelled, isTrue);
      expect(s.entries[0].isReversal, isFalse);
      expect(s.entries[1].isReversal, isTrue);
      expect(s.entries[1].income, 35.5);
      expect(s.balance, 1000, reason: 'back where it started');
    });

    test('whose line it is: the administrator\'s', () {
      List<StatementEntry> of(StatementScope sc, {String? emp}) =>
          buildAccountStatement(
            buys: const [],
            transfers: const [],
            expenses: [_x('x1', 10, at(9))],
            start: start,
            end: end,
            scope: sc,
            employeeId: emp,
          ).entries;
      expect(of(StatementScope.all).length, 1);
      expect(of(StatementScope.me).length, 1);
      expect(of(StatementScope.employee, emp: 'sami'), isEmpty);
    });

    test('one account at a time', () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: const [],
        expenses: [
          _x('x1', 10, at(9)),
          _x('x2', 20, at(10), ex: 'e2'),
        ],
        start: start,
        end: end,
        exchangeId: 'e2',
      );
      expect(s.entries.length, 1);
      expect(s.totalOutgoing, 20);
    });

    test('the opening balance counts the commissions since the start', () {
      // the account holds 964.50 now; a commission of 35.50 was taken today
      final opening = openingBalanceAt(
        currentBalance: 964.5,
        buys: const [],
        transfers: const [],
        expenses: [_x('x1', 35.5, at(10))],
        start: start,
      );
      expect(opening, 1000);
      // taken and cancelled today: no net effect
      final cancelledToo = openingBalanceAt(
        currentBalance: 1000,
        buys: const [],
        transfers: const [],
        expenses: [_x('x1', 35.5, at(10), cancelledAt: at(11))],
        start: start,
      );
      expect(cancelledToo, 1000);
      // before the period: not counted
      final before = openingBalanceAt(
        currentBalance: 964.5,
        buys: const [],
        transfers: const [],
        expenses: [_x('x1', 35.5, DateTime(2026, 10, 1))],
        start: start,
      );
      expect(before, 964.5);
    });
  });

  group('the commission dialog', () {
    testWidgets(
        'it shows the account, its code and balance, and the three fields',
        (tester) async {
      await _open(tester);
      expect(find.text('خصم عمولة'), findsOneWidget);
      expect(find.text('الرحالة — بهار روز'), findsOneWidget);
      expect(
        tester.widget<Text>(_f('expense-balance')).data,
        contains('X-1'),
        reason: 'our account code',
      );
      expect(
        tester.widget<Text>(_f('expense-balance')).data,
        contains('1,000'),
      );
      expect(_f('expense-code'), findsOneWidget);
      expect(_f('expense-amount'), findsOneWidget);
      expect(_f('expense-note'), findsOneWidget);
      expect(
        tester.widget<TextField>(_f('expense-note')).controller!.text,
        'عمولة',
        reason: 'just the word, ready to be completed',
      );
    });

    testWidgets('code, value and what it is for go to the server',
        (tester) async {
      final fake = await _open(tester);
      await tester.enterText(_f('expense-code'), ' C-77 ');
      await tester.enterText(_f('expense-amount'), '35.5');
      await tester.enterText(_f('expense-note'), 'عمولة شهر 10');
      await tester.tap(_f('expense-save'));
      await tester.pumpAndSettle();
      expect(fake.recorded, [
        {
          'exchange': 'e1',
          'amount': 35.5,
          'code': 'C-77',
          'note': 'عمولة شهر 10',
        },
      ]);
      // ready for the next one
      expect(tester.widget<TextField>(_f('expense-amount')).controller!.text,
          isEmpty);
      expect(tester.widget<TextField>(_f('expense-note')).controller!.text,
          kDefaultExpenseNote);
    });

    testWidgets('the code is optional', (tester) async {
      final fake = await _open(tester);
      await tester.enterText(_f('expense-amount'), '10');
      await tester.tap(_f('expense-save'));
      await tester.pumpAndSettle();
      expect(fake.recorded.single['code'], isNull);
    });

    testWidgets('nothing is sent without a value or without a note',
        (tester) async {
      final fake = await _open(tester);
      await tester.tap(_f('expense-save'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب قيمة العمولة.'), findsOneWidget);

      await tester.enterText(_f('expense-amount'), '10');
      await tester.enterText(_f('expense-note'), '   ');
      await tester.tap(_f('expense-save'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب ما تخصّ به العمولة.'), findsOneWidget);
      expect(fake.recorded, isEmpty);
    });

    testWidgets('more than the balance is refused, naming the balance',
        (tester) async {
      final fake = await _open(tester);
      await tester.enterText(_f('expense-amount'), '1000.01');
      await tester.tap(_f('expense-save'));
      await tester.pumpAndSettle();
      expect(fake.recorded, isEmpty);
      expect(find.textContaining('الرصيد لا يكفي'), findsOneWidget);
      expect(find.textContaining('1,000'), findsWidgets);
    });

    testWidgets('today\'s commissions can be cancelled with a password',
        (tester) async {
      final fake = await _open(tester, today: [
        _x('x1', 35.5, DateTime.now(), code: 'C-1'),
        _x('x2', 10, DateTime.now(), cancelledAt: DateTime.now()),
        _x('x3', 99, DateTime.now(), ex: 'other'),
      ]);
      // only this account's, and a cancelled one has no cancel button
      expect(_f('expense-x1'), findsOneWidget);
      expect(_f('expense-x2'), findsOneWidget);
      expect(_f('expense-x3'), findsNothing);
      expect(_f('expense-cancel-x1'), findsOneWidget);
      expect(_f('expense-cancel-x2'), findsNothing);

      await tester.tap(_f('expense-cancel-x1'));
      await tester.pumpAndSettle();
      // a reason and the password are both needed
      await tester.tap(_f('cancel-expense-confirm'));
      await tester.pumpAndSettle();
      expect(fake.cancelled, isEmpty);
      expect(find.textContaining('سبب الإلغاء'), findsWidgets);

      fake.cancelResult = const CancelWrongPassword(3);
      await tester.enterText(_f('cancel-expense-reason'), 'مبلغ خاطئ');
      await tester.enterText(find.byType(TextField).last, 'bad');
      await tester.tap(_f('cancel-expense-confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('المحاولات المتبقية: 3'), findsOneWidget);

      fake.cancelResult = const CancelDone(1000);
      await tester.tap(_f('cancel-expense-confirm'));
      await tester.pumpAndSettle();
      expect(fake.cancelled.last, 'x1|مبلغ خاطئ|bad');
      expect(_f('cancel-expense-confirm'), findsNothing,
          reason: 'the cancel dialog closed');
    });
  });

  test('the server errors read in plain Arabic', () {
    expect(friendlyError('insufficient_balance detail: balance 10, expense 50'),
        contains('خصم هذه العمولة'));
    expect(friendlyError('expense_amount_invalid'), contains('غير صحيحة'));
    expect(friendlyError('expense_note_required'), contains('ما تخصّ'));
    // an exit above the balance keeps its own message
    expect(friendlyError('insufficient_balance'), contains('لهذه الحوالة'));
  });

  group('wiring', () {
    test('the button is for the administrator only, one per account row', () {
      final src =
          File('lib/features/companies/presentation/accounts_screen.dart')
              .readAsStringSync();
      expect(src.replaceAll(RegExp(r'\s+'), ' '),
          contains('onExpense: ref.watch(isEmployeeProvider) ? null'));
      expect(src, contains("ValueKey('expense-\${ex.id}')"));
      expect(src, contains('showAccountExpenseDialog('));
    });

    test('the statement and its PDF carry the commissions', () {
      final screen = File(
              'lib/features/companies/presentation/account_statement_screen.dart')
          .readAsStringSync();
      expect(screen, contains('expenses: data.expenses'));
      expect(screen, contains('label: e.note'));
      final pdf = File('lib/shared/pdf_export_period.dart').readAsStringSync();
      expect(pdf, contains("if (showLabel) 'البيان'"));
    });

    test('a failure reading them never takes the statement down', () {
      final prov = File(
              'lib/features/companies/presentation/account_statement_providers.dart')
          .readAsStringSync();
      expect(prov, contains('} catch (_) {'));
    });

    test('the server side is in 0072', () {
      final sql = File('supabase/migrations/0072_account_expenses.sql')
          .readAsStringSync();
      for (final must in [
        'create table if not exists account_expenses',
        'function record_account_expense',
        'function admin_cancel_expense',
        "raise exception 'insufficient_balance'",
        "raise exception 'cancel_day_passed'",
        "'account_expenses'",
      ]) {
        expect(sql, contains(must), reason: must);
      }
    });
  });
}
