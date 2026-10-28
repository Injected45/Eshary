import 'package:eshary/core/theme.dart';
import 'package:eshary/features/adjustments/domain/balance_adjustment.dart';
import 'package:eshary/features/companies/domain/account_statement.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/exchange_rates/presentation/lyd_method_selector.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/treasury/data/treasury_repository.dart';
import 'package:eshary/features/treasury/domain/lyd_treasury.dart';
import 'package:eshary/features/treasury/domain/profit_report.dart';
import 'package:eshary/features/treasury/domain/treasury_position.dart';
import 'package:eshary/features/treasury/presentation/dinar_treasury_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 9);

Map<String, dynamic> _summaryJson() => {
      'open': true,
      'started_at': '2026-10-28T07:00:00Z',
      'opening_cash': 5000,
      'opening_bank': 20000,
      'cash': 8800,
      'bank': 34100,
      'flows': {
        'sales_cash': 7350,
        'sales_bank': 14800,
        'buys_cash': 3550,
        'buys_bank': 700,
      },
      'movements': [
        {
          'id': 'm1',
          'kind': 'count_short',
          'pocket': null,
          'amount': 50,
          'note': 'جرد',
          'created_at': '2026-10-28T18:00:00Z',
        },
        {
          'id': 'm2',
          'kind': 'cash_to_bank',
          'pocket': null,
          'amount': 2000,
          'note': null,
          'created_at': '2026-10-28T12:00:00Z',
        },
      ],
      'counts': [
        {
          'id': 'c1',
          'expected': 8300,
          'counted': 8250,
          'difference': -50,
          'posted': true,
          'note': null,
          'created_at': '2026-10-28T18:00:00Z',
        },
      ],
    };

class _FakeRepo implements TreasuryRepository {
  _FakeRepo(this.summary);
  LydSummary summary;
  final calls = <String>[];

  @override
  Future<LydSummary> lydSummary(DateTime from, DateTime to) async => summary;
  @override
  Future<void> lydOpen({required double cash, required double bank}) async =>
      calls.add('open $cash $bank');
  @override
  Future<void> lydMove({
    required String kind,
    String? pocket,
    required double amount,
    String? note,
  }) async =>
      calls.add('move $kind $pocket $amount');
  @override
  Future<LydCount> lydCount({
    required double counted,
    String? note,
    bool post = true,
  }) async {
    calls.add('count $counted $post');
    return LydCount(
      expected: 8800,
      counted: counted,
      difference: counted - 8800,
      posted: post,
      note: note,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<TreasuryPosition>> positions() async => const [];
  @override
  Future<void> setCost(String exchangeId, double rate) async {}
  @override
  Future<List<ProfitRow>> profitReport(DateTime from, DateTime to) async =>
      const [];
  @override
  Future<List<CostEvent>> costHistory(String exchangeId) async => const [];
}

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
    'NotoNaskhArabic-Medium.ttf',
    'NotoNaskhArabic-Bold.ttf',
    'NotoNaskhArabic-SemiBold.ttf',
  ]);
  await load('Almarai', [
    'Almarai-Light.ttf',
    'Almarai-Regular.ttf',
    'Almarai-Bold.ttf',
    'Almarai-ExtraBold.ttf',
  ]);
}

Future<_FakeRepo> _open(
  WidgetTester tester,
  LydSummary summary, {
  double width = 400,
}) async {
  await _loadFonts();
  final repo = _FakeRepo(summary);
  await tester.binding.setSurfaceSize(Size(width, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [treasuryRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: DinarTreasuryScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('the dinar treasury as the database sends it', () {
    test('closed', () {
      expect(LydSummary.fromJson(const {'open': false}).open, isFalse);
    });
    test('open: balances, flows, movements and counts', () {
      final s = LydSummary.fromJson(_summaryJson());
      expect(s.cash, 8800);
      expect(s.bank, 34100);
      expect(s.total, 42900);
      expect(s.netCash, 7350 - 3550);
      expect(s.netBank, 14800 - 700);
      expect(s.movements.first.label, 'عجز جرد');
      expect(s.movements.first.isOut, isTrue);
      expect(s.movements.last.label, 'من الصندوق إلى المصرف');
      expect(
        s.movements.last.isIn || s.movements.last.isOut,
        isFalse,
        reason: 'a transfer between pockets adds nothing',
      );
      expect(s.counts.single.difference, -50);
      expect(s.counts.single.posted, isTrue);
    });
  });

  group('the payment method', () {
    test('labels', () {
      expect(lydMethodLabel('cash'), 'نقدًا');
      expect(lydMethodLabel('bank'), 'مصرفي');
      expect(lydMethodLabel(null), '—');
    });
    test('read from the operations', () {
      final t = Transfer.fromJson({
        'id': 't',
        'owner_id': 'o',
        'company_id': 'c',
        'exchange_id': 'x',
        'beneficiary_name': 'م',
        'beneficiary_account_company': null,
        'beneficiary_code': null,
        'amount': 100,
        'reference': 'R',
        'status': 'archived',
        'created_at': '2026-10-28T09:00:00Z',
        'archived_at': '2026-10-28T09:00:00Z',
        'created_by_employee_id': null,
        'cancelled_at': null,
        'rate': 7.3,
        'lyd_amount': 730,
        'lyd_method': 'bank',
      });
      expect(t.lydMethod, 'bank');
      final b = CurrencyBuy.fromJson({
        'id': 'b',
        'owner_id': 'o',
        'my_company_id': 'c',
        'exchange_id': 'x',
        'client_id': null,
        'client_from_account': null,
        'usd_amount': 100,
        'rate': 7.1,
        'lyd_amount': 710,
        'lyd_method': 'cash',
        'reference': '',
        'status': 'archived',
        'created_at': '2026-10-28T09:00:00Z',
        'archived_at': '2026-10-28T09:00:00Z',
        'created_by_employee_id': null,
        'cancelled_at': null,
      });
      expect(b.lydMethod, 'cash');
    });
  });

  group('the balance adjustment in the account statement', () {
    final adj = BalanceAdjustment(
      id: 'a1',
      exchangeId: 'x',
      balanceBefore: 10000,
      balanceAfter: 9950,
      delta: -50,
      reason: 'مطابقة كشف بهاروز',
      createdAt: _t0,
    );
    test('a line with its reason, on the right side', () {
      final st = buildAccountStatement(
        buys: const [],
        transfers: const [],
        adjustments: [adj],
        start: _t0.subtract(const Duration(hours: 1)),
        end: _t0.add(const Duration(hours: 1)),
        openingBalance: 10000,
      );
      expect(st.entries.single.outgoing, 50);
      expect(st.entries.single.note, 'تسوية رصيد: مطابقة كشف بهاروز');
      expect(st.balance, 9950);
    });
    test('the opening balance accounts for it', () {
      final opening = openingBalanceAt(
        currentBalance: 9950,
        buys: const [],
        transfers: const [],
        adjustments: [adj],
        start: _t0.subtract(const Duration(hours: 1)),
      );
      expect(opening, 10000);
    });
    test('an increase is income', () {
      final up = BalanceAdjustment(
        id: 'a2',
        exchangeId: 'x',
        balanceBefore: 100,
        balanceAfter: 130,
        delta: 30,
        reason: 'تصحيح',
        createdAt: _t0,
      );
      final st = buildAccountStatement(
        buys: const [],
        transfers: const [],
        adjustments: [up],
        start: _t0.subtract(const Duration(hours: 1)),
        end: _t0.add(const Duration(hours: 1)),
      );
      expect(st.entries.single.income, 30);
    });
    test('the database\'s answer', () {
      expect(
        parseAdjustResult(const {'ok': true, 'balance_after': 9950}),
        isA<AdjustDone>(),
      );
      final w = parseAdjustResult(
        const {'ok': false, 'error': 'wrong_password', 'remaining': 3},
      );
      expect(w, isA<AdjustWrongPassword>());
      expect((w as AdjustWrongPassword).remaining, 3);
      expect(
        parseAdjustResult(const {'ok': false, 'error': 'locked'}),
        isA<AdjustLocked>(),
      );
    });
  });

  group('the screen', () {
    testWidgets('not open yet: the opening form', (tester) async {
      final repo = await _open(tester, const LydSummary(open: false));
      expect(find.byKey(const ValueKey('lyd-opening')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lyd-open-cash')),
        '5000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lyd-open-bank')),
        '20,000',
      );
      await tester.tap(find.byKey(const ValueKey('lyd-open-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['open 5000.0 20000.0']);
    });

    testWidgets('open: the box, the bank, the flows, the movements',
        (tester) async {
      await _open(tester, LydSummary.fromJson(_summaryJson()));
      expect(find.text('8,800.00 د.ل'), findsOneWidget);
      expect(find.text('34,100.00 د.ل'), findsOneWidget);
      expect(find.text('42,900.00 د.ل'), findsOneWidget);
      expect(find.text('عجز جرد'), findsOneWidget);
      expect(find.textContaining('المتوقع 8,300.00 د.ل'), findsOneWidget);
    });

    testWidgets('a deposit into the bank', (tester) async {
      final repo = await _open(tester, LydSummary.fromJson(_summaryJson()));
      await tester.tap(find.byKey(const ValueKey('lyd-deposit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('المصرف'),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('lyd-amount')), '1500');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lyd-amount-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['move in bank 1500.0']);
    });

    testWidgets('the count shows the shortage before saving', (tester) async {
      final repo = await _open(tester, LydSummary.fromJson(_summaryJson()));
      await tester.tap(find.byKey(const ValueKey('lyd-count')));
      await tester.pumpAndSettle();
      expect(find.text('المتوقع في الصندوق: 8,800.00 د.ل'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('lyd-counted')), '8750');
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lyd-count-diff'))).data,
        'عجز 50.00 د.ل',
      );
      await tester.tap(find.byKey(const ValueKey('lyd-count-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['count 8750.0 true']);
    });

    testWidgets('a narrow 320 phone: nothing overflows', (tester) async {
      await _open(tester, LydSummary.fromJson(_summaryJson()), width: 320);
      expect(tester.takeException(), isNull);
    });
  });
}
