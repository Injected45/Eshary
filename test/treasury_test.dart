import 'package:eshary/core/theme.dart';
import 'package:eshary/features/treasury/data/treasury_repository.dart';
import 'package:eshary/features/treasury/domain/profit_report.dart';
import 'package:eshary/features/treasury/domain/treasury_position.dart';
import 'package:eshary/features/treasury/presentation/treasury_providers.dart';
import 'package:eshary/features/treasury/presentation/treasury_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TreasuryPosition _p(
  String id,
  double balance, {
  double? cost,
  String name = 'بهاروز',
}) =>
    TreasuryPosition(
      exchangeId: id,
      companyName: 'الرحالة الأولى',
      accountName: name,
      balance: balance,
      costRate: cost,
      bookValue: cost == null ? null : (balance * cost * 100).round() / 100,
      costUpdatedAt: null,
    );

class _FakeRepo implements TreasuryRepository {
  final calls = <(String, double)>[];
  @override
  Future<List<TreasuryPosition>> positions() async => const [];
  @override
  Future<void> setCost(String exchangeId, double rate) async =>
      calls.add((exchangeId, rate));
  @override
  Future<List<ProfitRow>> profitReport(DateTime from, DateTime to) async =>
      const [];
  @override
  Future<List<CostEvent>> costHistory(String exchangeId) async => const [];
}

/// Real app fonts, so widths match a phone instead of the wide test font.
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
  List<TreasuryPosition> rows, {
  double width = 400,
}) async {
  await _loadFonts();
  final repo = _FakeRepo();
  await tester.binding.setSurfaceSize(Size(width, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryProvider.overrideWith((ref) async => rows),
        treasuryRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: TreasuryScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('the totals', () {
    test('only the costed accounts are averaged', () {
      final t = TreasuryTotals.of([
        _p('a', 12000, cost: 7.2),
        _p('b', 3000, cost: 7.0),
        _p('c', 500), // no opening cost yet
        _p('d', 0), // empty, nothing to cost
      ]);
      expect(t.costedUsd, 15000);
      expect(t.bookValue, 86400 + 21000);
      expect(t.averageCost, closeTo(107400 / 15000, 1e-12)); // 7.16
      expect(t.uncosted, 1, reason: 'an empty account needs no cost');
    });
    test('nothing costed: no average', () {
      expect(TreasuryTotals.of([_p('a', 100)]).averageCost, isNull);
    });
    test('the rows as the database sends them', () {
      final p = TreasuryPosition.fromJson(const {
        'exchange_id': 'x',
        'company_name': 'الرحالة',
        'account_name': 'بهاروز',
        'balance': 110,
        'cost_rate': 7.123456,
        'book_value': 783.58,
        'cost_updated_at': '2026-10-28T12:00:00Z',
      });
      expect(p.costRate, 7.123456);
      expect(formatCost(p.costRate!), '7.1235');
      expect(p.bookValue, 783.58);
      final none = TreasuryPosition.fromJson(const {
        'exchange_id': 'y',
        'company_name': 'ا',
        'account_name': 'ب',
        'balance': 0,
        'cost_rate': null,
        'book_value': null,
        'cost_updated_at': null,
      });
      expect(none.hasCost, isFalse);
    });
  });

  group('the screen', () {
    testWidgets('the average cost, each account and its book value',
        (tester) async {
      await _open(tester, [
        _p('a', 12000, cost: 7.2),
        _p('b', 3000, cost: 7.0, name: 'الصحراء'),
      ]);
      expect(find.text('7.1600 د.ل'), findsOneWidget);
      expect(find.text('7.2000 د.ل'), findsOneWidget);
      expect(find.text('86,400.00 د.ل'), findsOneWidget);
      expect(find.text('\$12,000.00'), findsOneWidget);
      expect(find.text('الصحراء'), findsOneWidget);
    });

    testWidgets('an account without a cost asks for the opening cost',
        (tester) async {
      final repo = await _open(tester, [_p('a', 110)]);
      expect(find.text('لم يُحدَّد'), findsOneWidget);
      expect(find.textContaining('بلا سعر تكلفة'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('set-opening-a')));
      await tester.pumpAndSettle();
      expect(find.text('سعر تكلفة أول المدة'), findsOneWidget);
      expect(find.textContaining('الآن \$110.00'), findsOneWidget);
      // nothing typed: cannot save
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('cost-save')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('cost-rate-field')),
        '7.10',
      );
      await tester.pump();
      expect(find.text('القيمة الدفترية: 781.00 د.ل'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cost-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, [('a', 7.10)]);
    });

    testWidgets('a costed account can be corrected, with a warning',
        (tester) async {
      await _open(tester, [_p('a', 1000, cost: 7.2)]);
      await tester.tap(find.byKey(const ValueKey('correct-cost-a')));
      await tester.pumpAndSettle();
      expect(find.text('تصحيح سعر التكلفة'), findsOneWidget);
      expect(
        find.textContaining('السعر الحالي 7.2000 سيُستبدل'),
        findsOneWidget,
      );
    });

    testWidgets('a narrow 320 phone and huge figures: nothing overflows',
        (tester) async {
      await _open(
        tester,
        [_p('a', 999999999.99, cost: 9.999999), _p('b', 123456789.12)],
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('لم يُحدَّد'), findsOneWidget);
    });

    testWidgets('no accounts', (tester) async {
      await _open(tester, const []);
      expect(find.text('لا توجد حسابات حتى الآن'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'no average to show');
    });
  });
}
