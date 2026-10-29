import 'dart:convert';
import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/ledger/data/ledger_repository.dart';
import 'package:eshary/features/ledger/domain/ledger.dart';
import 'package:eshary/features/reports/data/reports_repository.dart';
import 'package:eshary/features/reports/domain/reports.dart';
import 'package:eshary/features/reports/presentation/debt_aging_screen.dart';
import 'package:eshary/features/reports/presentation/employees_report_screen.dart';
import 'package:eshary/features/reports/presentation/period_report_screen.dart';
import 'package:eshary/features/reports/presentation/profit_loss_screen.dart';
import 'package:eshary/features/reports/presentation/reports_screen.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The reports of 0095. The fixtures are what the database really sent in
// supabase/tests/reports95_test.mjs (WRITE_FIXTURES=1): a cash book with 3
// sales (49.25 profit) and a purchase, a bank book with one sale (80 profit),
// an employee «سالم», a customer owing 100 this week, one 50 over 90 days
// and over his limit, a seller we owe 70.

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

class _Repo implements ReportsRepository {
  int periods = 0;
  @override
  Future<PeriodReport> period(DateTime from, DateTime to) async {
    periods++;
    return PeriodReport.fromJson(_fixture('report_period.json'));
  }

  @override
  Future<DebtAging> debtAging() async =>
      DebtAging.fromJson(_fixture('debt_aging.json'));
}

// what ledger_income_statement sends: 1,190 of profit now (1,250 from
// selling, 60 of commissions), 900 in the period before
final _plNow = IncomeStatement.fromJson(const {
  'lines': [
    {'account': '4100', 'name': 'نتيجة بيع العملة', 'amount': 1250},
    {'account': '5300', 'name': 'عمولات', 'amount': -60},
  ],
  'net': 1190,
});
final _plBefore = IncomeStatement.fromJson(const {
  'lines': [
    {'account': '4100', 'name': 'نتيجة بيع العملة', 'amount': 950},
    {'account': '5300', 'name': 'عمولات', 'amount': -50},
  ],
  'net': 900,
});

class _Ledger implements LedgerRepository {
  final books = <String?>[];
  DateTime? lastFrom;

  @override
  Future<IncomeStatement> incomeStatement(
    DateTime from,
    DateTime to, {
    String? book,
    double factor = 1,
  }) async {
    books.add(book);
    // the first of the two reads is the period, the second the one before
    final isBefore = lastFrom != null && from.isBefore(lastFrom!);
    lastFrom = from;
    return isBefore ? _plBefore : _plNow;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _fonts() async {
  final loader = FontLoader('Almarai');
  for (final f in [
    'Almarai-Regular.ttf',
    'Almarai-Bold.ttf',
    'Almarai-ExtraBold.ttf',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/$f'));
  }
  await loader.load();
}

Future<_Repo> _open(
  WidgetTester tester,
  Widget screen, {
  _Ledger? ledger,
}) async {
  await _fonts();
  final repo = _Repo();
  await tester.binding.setSurfaceSize(const Size(360, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(repo),
        ledgerRepositoryProvider.overrideWithValue(ledger ?? _Ledger()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ),
  );
  // a screen that reloads for ever never settles: this would time out
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('what the database sends', () {
    test('the period', () {
      final r = PeriodReport.fromJson(_fixture('report_period.json'));
      expect(r.books.map((b) => b.book), ['cash', 'bank']);
      final cash = r.books.first;
      expect(cash.saleN, 3);
      expect(cash.profit, 49.25);
      expect(cash.avgSellRate, closeTo(1666 / 170, 1e-9));
      expect(cash.avgBuyRate, closeTo(9.6, 1e-9));
      expect(cash.usdEnd - cash.usdStart, cash.buyUsd - cash.saleUsd);
      expect(r.profit, closeTo(129.25, 1e-9));
      expect(r.lyd.open, isTrue);
      expect(r.creditGiven, 196);
      expect(r.cancelledN, 1);
      expect(r.byEmployee.map((e) => e.label), containsAll(['المدير', 'سالم']));
      expect(r.byDay.single.saleN, 4);
    });

    // debt_aging.json comes from supabase/tests/debts96_test.mjs: «منير» owes
    // 50 for 100 days (over his limit of 10, never collected), «كريم» 196
    // this week; we owe «بائع» 130 (80 for 40 days, 50 new)
    test('the debts, both sides', () {
      final a = DebtAging.fromJson(_fixture('debt_aging.json'));
      expect(a.debtors.first.name, 'منير');
      expect(a.debtors.first.overLimit, isTrue);
      expect(a.debtors.first.lastSettle, isNull);
      expect(a.older, 50);
      expect(a.d7, 196);
      expect(a.owedToUs, 246);
      expect(a.weOwe, 130);
      expect(a.net, 116);
      // كريم has no limit at all (null = no credit, 0091): any debt is over it
      expect(a.overLimit, 2);
      final s = a.creditors.single;
      expect(s.code, '7000');
      expect(s.late30, 80);
      expect(s.lastSettle, isNotNull);
      expect(s.title, 'بائع — أنزار · 7000');
    });

    test('the follow-up filters and the order', () {
      final a = DebtAging.fromJson(_fixture('debt_aging.json'));
      List<String> names(List<DebtRow> rows) => rows.map((r) => r.name).toList();
      expect(names(debtView(a, side: DebtSide.ours)), ['كريم', 'منير']);
      expect(names(debtView(a, side: DebtSide.ours, sort: DebtSort.oldest)),
          ['منير', 'كريم']);
      expect(names(debtView(a, side: DebtSide.ours, filter: DebtFilter.late90)),
          ['منير']);
      expect(
        names(debtView(a, side: DebtSide.ours, filter: DebtFilter.overLimit)),
        ['كريم', 'منير'],
      );
      // never collected for 100 days; كريم paid yesterday
      expect(
        names(debtView(a, side: DebtSide.ours, filter: DebtFilter.noSettle30)),
        ['منير'],
      );
      expect(names(debtView(a, side: DebtSide.ours, search: '5521')), ['كريم']);
      expect(names(debtView(a, side: DebtSide.theirs, filter: DebtFilter.late30)),
          ['بائع']);
    });

    test('the change against the previous period', () {
      expect(PeriodReport.change(150, 100), closeTo(0.5, 1e-9));
      expect(PeriodReport.change(50, 100), closeTo(-0.5, 1e-9));
      expect(PeriodReport.change(50, 0), isNull);
    });
  });

  group('the screens', () {
    testWidgets('the period report loads once and shows the profit',
        (tester) async {
      final repo = await _open(tester, const PeriodReportScreen());
      expect(repo.periods, 1);
      expect(find.text('+129.25 د.ل'), findsOneWidget);
      expect(find.text('الدفتر نقدي'), findsOneWidget);
      expect(find.text('الدفتر مصرفي'), findsOneWidget);
      expect(find.text('الآجل'), findsOneWidget);
    });

    testWidgets('choosing another period asks once more', (tester) async {
      final repo = await _open(tester, const PeriodReportScreen());
      await tester.tap(find.text('آخر 7 أيام'));
      await tester.pumpAndSettle();
      expect(repo.periods, 2);
    });

    testWidgets('the employees', (tester) async {
      await _open(tester, const EmployeesReportScreen());
      expect(find.text('سالم'), findsOneWidget);
      expect(find.text('المدير'), findsOneWidget);
    });

    testWidgets('the debts list: ours, then theirs', (tester) async {
      await _open(tester, const DebtAgingScreen());
      expect(find.textContaining('منير'), findsOneWidget);
      expect(find.textContaining('كريم'), findsOneWidget);
      expect(find.text('2 تجاوز الحد'), findsOneWidget);
      await tester.tap(find.text('علينا (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('بائع'), findsOneWidget);
      expect(find.textContaining('منير'), findsNothing);
      await tester.tap(find.text('لنا (2)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('debts-search')), '5521');
      await tester.pumpAndSettle();
      expect(find.textContaining('كريم'), findsOneWidget);
      expect(find.textContaining('منير'), findsNothing);
    });

    testWidgets('the reports tab lists them, the daily one first',
        (tester) async {
      // inside the home shell's Scaffold in the app
      await _open(tester, const Scaffold(body: ReportsScreen()));
      expect(kReports.first.keyName, 'period');
      expect(
        kReports.map((r) => r.keyName),
        ['period', 'profit_loss', 'employees', 'aging', 'party', 'ledger'],
      );
    });

    testWidgets('profit and loss: the lines, the net, the period before',
        (tester) async {
      final ledger = _Ledger();
      await _open(tester, const ProfitLossScreen(), ledger: ledger);
      expect(ledger.books, [null, null], reason: 'this period and the one before');
      expect(find.text('+1,190.00 د.ل'), findsWidgets);
      expect(find.text('نتيجة بيع العملة'), findsOneWidget);
      expect(find.text('عمولات'), findsOneWidget);
      expect(find.textContaining('+32 % عن الفترة السابقة'), findsOneWidget);
      // one book
      await tester.tap(find.text('النقدي'));
      await tester.pumpAndSettle();
      expect(ledger.books.skip(2), ['cash', 'cash']);
    });
  });

  group('PDF', () {
    test('profit and loss builds', () async {
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildProfitLossReport(
        now: _plNow,
        before: _plBefore,
        first: DateTime(2026, 10, 1),
        last: DateTime(2026, 10, 29),
        bookTitle: 'الدفتران معًا',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('the three reports build', () async {
      final pdf = await PdfExport.load();
      final r = PeriodReport.fromJson(_fixture('report_period.json'));
      final a = DebtAging.fromJson(_fixture('debt_aging.json'));
      final day = DateTime(2026, 10, 29);
      for (final bytes in [
        await pdf.buildPeriodReport(
          report: r,
          first: day,
          last: day,
          exportedBy: 'المدير',
        ),
        await pdf.buildEmployeesReport(report: r, first: day, last: day),
        await pdf.buildDebtAgingReport(aging: a),
      ]) {
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });
}
