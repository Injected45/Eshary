import 'package:eshary/core/theme.dart';
import 'package:eshary/features/ledger/data/ledger_repository.dart';
import 'package:eshary/features/ledger/domain/ledger.dart';
import 'package:eshary/features/ledger/presentation/ledger_screen.dart';
import 'package:eshary/features/ledger/presentation/reconcile_dialog.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 29, 9);

final _income = IncomeStatement.fromJson({
  'lines': [
    {'account': '4100', 'name': 'نتيجة بيع العملة', 'amount': 420.5},
    {'account': '5100', 'name': 'خسائر تسوية الأرصدة', 'amount': -70},
    {'account': '5200', 'name': 'عجز الجرد', 'amount': -50},
  ],
  'net': 300.5,
});

final _sheet = BalanceSheet.fromJson({
  'balances': {
    '1100': 8250,
    '1110': 21650,
    '1200': 50,
    '1300': 10479.5,
    '3100': -40000,
    '3200': -74,
    'profit': -355.5,
  },
  'receivable': 450,
  'payable': 400,
  'inventory': [
    {
      'exchange_id': 'e1',
      'company_name': 'الرحالة',
      'account_name': 'بهاروز',
      'balance': 1485,
      'cost_rate': 7.057,
      'book_value': 10479.65,
      'ledger_value': 10479.5,
    },
  ],
});

final _trial = [
  TrialLine.fromJson(
    {'account': '1100', 'name': 'الصندوق', 'debit': 9000, 'credit': 750},
  ),
  TrialLine.fromJson(
    {'account': '3100', 'name': 'رأس المال', 'debit': 0, 'credit': 8250},
  ),
];

class _FakeRepo implements LedgerRepository {
  final calls = <String>[];

  @override
  Future<IncomeStatement> incomeStatement(
    DateTime from,
    DateTime to, {
    String? book,
    double factor = 1,
  }) async {
    calls.add('income ${book ?? 'all'} $factor');
    return _income;
  }

  @override
  Future<BalanceSheet> balanceSheet(
    DateTime at, {
    String? book,
    double factor = 1,
  }) async =>
      _sheet;
  @override
  Future<List<TrialLine>> trialBalance(
    DateTime to, {
    String? book,
    double factor = 1,
  }) async =>
      _trial;
  @override
  Future<Journal> journal(DateTime from, DateTime to, {String? book}) async =>
      Journal.fromJson({
        'total': 2,
        'lines': [
          {
            'at': '2026-10-29T09:00:00Z',
            'source': 'sale',
            'source_id': 's1',
            'ref': 'Rh0101',
            'account': '1100',
            'name': 'الصندوق',
            'amount': 750,
          },
          {
            'at': '2026-10-29T09:00:00Z',
            'source': 'sale',
            'source_id': 's1',
            'ref': 'Rh0101',
            'account': '1300',
            'name': 'مخزون الدولار بالتكلفة',
            'amount': -750,
          },
        ],
      });
  @override
  Future<List<PeriodClose>> closes() async => [
        PeriodClose.fromJson({
          'id': 'c1',
          'period_end': '2026-10-28T21:59:59Z',
          'net_profit': 120,
          'intact': false,
        }),
      ];
  @override
  Future<double> closePeriod(DateTime end, {String? note}) async {
    calls.add('close');
    return 300.5;
  }

  @override
  Future<Reconciliation> reconcile({
    required String exchangeId,
    required DateTime at,
    required double theirBalance,
    String? note,
  }) async {
    calls.add('reconcile $exchangeId $theirBalance');
    return Reconciliation(
      at: at,
      theirBalance: theirBalance,
      ourBalance: 990,
      difference: theirBalance - 990,
    );
  }

  @override
  Future<List<Reconciliation>> reconciliations(String exchangeId) async =>
      const [];
}

/// The app's own fonts: the test font is far wider and would overflow a
/// 320 phone that the real one fits.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('NotoArabic', [
    'NotoNaskhArabic-Regular.ttf',
    'NotoNaskhArabic-Bold.ttf',
  ]);
  await load('Almarai', [
    'Almarai-Regular.ttf',
    'Almarai-Bold.ttf',
    'Almarai-ExtraBold.ttf',
  ]);
}

Future<_FakeRepo> _pump(WidgetTester tester, Widget child,
    {double width = 400}) async {
  await _loadFonts();
  final repo = _FakeRepo();
  await tester.binding.setSurfaceSize(Size(width, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('the statements as the database sends them', () {
    test('the income statement: income and expenses apart', () {
      expect(_income.income.single.name, 'نتيجة بيع العملة');
      expect(_income.expenses.length, 2);
      expect(_income.net, 300.5);
    });
    test('the balance sheet balances', () {
      expect(_sheet.totalAssets, 8250 + 21650 + 450 + 10479.5);
      expect(_sheet.profitToDate, 355.5);
      expect(_sheet.totalLiabilitiesAndEquity, _sheet.totalAssets);
      expect(_sheet.inventory.single.difference, -0.15);
    });
    test('the trial balance totals, in cents', () {
      final t = trialTotals(_trial);
      expect(t.debit, 9000);
      expect(t.credit, 9000);
      expect(_trial.first.balance, 8250);
    });
    test('the ledger groups', () {
      expect(ledgerGroupOf('1100'), LedgerGroup.asset);
      expect(ledgerGroupOf('4100'), LedgerGroup.income);
      expect(ledgerGroupOf('5300'), LedgerGroup.expense);
    });
  });

  group('the screen', () {
    testWidgets('the income statement by default', (tester) async {
      await _pump(tester, const LedgerScreen());
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ledger-net'))).data,
        '300.50 د.ل',
      );
      expect(find.text('عجز الجرد'), findsOneWidget);
    });

    testWidgets('the balance sheet says it balances', (tester) async {
      await _pump(tester, const LedgerScreen());
      await tester.tap(find.byKey(const ValueKey('ledger-tab-balance')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ledger-balanced'))).data,
        'الميزانية متوازنة ✓',
      );
      expect(find.textContaining('فرق'), findsOneWidget);
    });

    testWidgets('the trial balance and the journal', (tester) async {
      await _pump(tester, const LedgerScreen());
      await tester.tap(find.byKey(const ValueKey('ledger-tab-trial')));
      await tester.pumpAndSettle();
      expect(find.text('متوازن ✓'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ledger-tab-journal')));
      await tester.pumpAndSettle();
      expect(find.textContaining('بيع · Rh0101'), findsOneWidget);
      expect(find.text('من حـ/ الصندوق'), findsOneWidget);
    });

    testWidgets('the closes: a changed past shows, and a new close',
        (tester) async {
      final repo = await _pump(tester, const LedgerScreen());
      await tester.tap(find.byKey(const ValueKey('ledger-tab-closes')));
      await tester.pumpAndSettle();
      expect(find.text('غير مطابق!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close-period-ok')));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c == 'close'), hasLength(1));
    });

    testWidgets('one book, or both converted at the factor typed (0093)',
        (tester) async {
      final repo = await _pump(tester, const LedgerScreen());
      expect(repo.calls.last, 'income all 1.0');
      await tester.enterText(
          find.byKey(const ValueKey('ledger-factor')), '0.98');
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'income all 0.98');
      await tester.tap(find.byKey(const ValueKey('ledger-book-cash')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'income cash 1.0');
      expect(find.byKey(const ValueKey('ledger-factor')), findsNothing);
    });

    testWidgets('a 320 phone: nothing overflows', (tester) async {
      await _pump(tester, const LedgerScreen(), width: 320);
      for (final t in ['balance', 'trial', 'journal', 'closes']) {
        await tester.tap(find.byKey(ValueKey('ledger-tab-$t')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: t);
      }
    });
  });

  testWidgets('reconciling: their balance against ours', (tester) async {
    final repo = await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showReconcileDialog(
              context,
              exchangeId: 'e1',
              accountName: 'بهاروز',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reconcile-theirs')),
      '1,015',
    );
    await tester.tap(find.byKey(const ValueKey('reconcile-save')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['reconcile e1 1015.0']);
    expect(find.text('رصيدنا في نفس الوقت: \$990.00'), findsOneWidget);
    expect(find.textContaining('الفرق: \$25.00'), findsOneWidget);
  });

  test('the three statements print', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pdf = await PdfExport.load();
    for (final bytes in [
      await pdf.buildIncomeStatement(
        statement: _income,
        start: _t0,
        end: _t0.add(const Duration(hours: 12)),
      ),
      await pdf.buildBalanceSheet(sheet: _sheet, at: _t0),
      await pdf.buildTrialBalance(lines: _trial, at: _t0),
    ]) {
      expect(bytes.length, greaterThan(1000));
    }
  });
}
