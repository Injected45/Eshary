import 'dart:convert';
import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/reports/data/reports_repository.dart';
import 'package:eshary/features/reports/domain/reports.dart';
import 'package:eshary/features/reports/presentation/debt_aging_screen.dart';
import 'package:eshary/features/reports/presentation/employees_report_screen.dart';
import 'package:eshary/features/reports/presentation/period_report_screen.dart';
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

Future<_Repo> _open(WidgetTester tester, Widget screen) async {
  await _fonts();
  final repo = _Repo();
  await tester.binding.setSurfaceSize(const Size(360, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reportsRepositoryProvider.overrideWithValue(repo)],
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

    test('the ageing', () {
      final a = DebtAging.fromJson(_fixture('debt_aging.json'));
      expect(a.debtors.first.name, 'منير');
      expect(a.debtors.first.overLimit, isTrue);
      expect(a.older, 50);
      expect(a.d7, 100);
      expect(a.weOwe, 70);
      expect(a.overLimit, 1);
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

    testWidgets('the ageing of the debts', (tester) async {
      await _open(tester, const DebtAgingScreen());
      expect(find.textContaining('منير'), findsOneWidget);
      expect(find.text('1 عميل تجاوز حد الدين.'), findsOneWidget);
      expect(find.text('الدائنون (علينا)'), findsOneWidget);
    });

    testWidgets('the reports tab lists them, the daily one first',
        (tester) async {
      // inside the home shell's Scaffold in the app
      await _open(tester, const Scaffold(body: ReportsScreen()));
      expect(kReports.first.keyName, 'period');
      expect(
        kReports.map((r) => r.keyName),
        ['period', 'employees', 'aging', 'party', 'ledger'],
      );
    });
  });

  group('PDF', () {
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
