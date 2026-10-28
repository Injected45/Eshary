import 'package:eshary/core/theme.dart';
import 'package:eshary/features/exchange_rates/domain/exchange_rates.dart';
import 'package:eshary/features/exchange_rates/presentation/rate_fields.dart';
import 'package:eshary/features/treasury/domain/profit_report.dart';
import 'package:eshary/features/treasury/presentation/profit_section.dart';
import 'package:eshary/shared/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProfitRow _row({
  String id = 'a',
  String name = 'بهاروز',
  double sold = 0,
  double sales = 0,
  double cost = 0,
  int unpriced = 0,
  double unpricedUsd = 0,
  double bought = 0,
  double paid = 0,
}) =>
    ProfitRow(
      exchangeId: id,
      companyName: 'الرحالة',
      accountName: name,
      soldUsd: sold,
      salesLyd: sales,
      costLyd: cost,
      profitLyd: ((sales - cost) * 100).round() / 100,
      exitsPriced: sold > 0 ? 1 : 0,
      exitsUnpriced: unpriced,
      unpricedUsd: unpricedUsd,
      boughtUsd: bought,
      boughtLyd: paid,
      entriesPriced: bought > 0 ? 1 : 0,
    );

void main() {
  group('a typed rate (the reviewer\'s "7,25" case)', () {
    test('a comma or the Arabic decimal mark is the decimal point', () {
      expect(parseRate('7,25'), 7.25);
      expect(parseRate('7.25'), 7.25);
      expect(parseRate('٧٫٢٥'), 7.25);
      expect(parseRate(' 7.1235 '), 7.1235);
    });
    test('not a number: 0', () {
      expect(parseRate('7.2.5'), 0);
      expect(parseRate('abc'), 0);
      expect(parseRate(''), 0);
    });
    test('the range the database accepts', () {
      expect(rateInRange(7.25), isTrue);
      expect(rateInRange(100), isTrue);
      expect(rateInRange(1), isFalse);
      expect(rateInRange(0.725), isFalse);
      expect(rateInRange(725), isFalse);
    });
    test('the rate field reads a comma as a point', () {
      final c = TextEditingController(text: '7,25');
      const r = ExchangeRates(sell: 7, buy: 7, canEdit: true);
      expect(effectiveRate(c, r, sell: true), 7.25);
    });
  });

  group('the cost after a buy, as the database averages it', () {
    test('the worked example', () {
      expect(
        costAfterBuy(balance: 10000, cost: 7.10, usd: 5000, rate: 7.40),
        closeTo(7.20, 1e-12),
      );
    });
    test('an empty account starts at the rate', () {
      expect(costAfterBuy(balance: 0, cost: 7.1, usd: 100, rate: 6.9), 6.9);
    });
  });

  group('the profit of a period', () {
    test('the worked example: 3,000 sold at 7.35 against a cost of 7.20', () {
      final t = ProfitTotals.of([
        _row(sold: 3000, sales: 22050, cost: 21600, bought: 5000, paid: 37000),
      ]);
      expect(t.profitLyd, 450);
      expect(t.avgSellRate, 7.35);
      expect(t.avgCostRate, 7.2);
      expect(t.marginPerUsd, 0.15);
      expect(t.marginPercent, closeTo(450 / 21600 * 100, 1e-9));
      expect(t.avgBuyRate, 7.4);
      expect(t.netLydFlow, 22050 - 37000);
    });
    test('accounts add up to the dirham (no binary fraction)', () {
      final t = ProfitTotals.of([
        _row(id: 'a', sold: 0.1, sales: 0.73, cost: 0.71),
        _row(id: 'b', sold: 0.2, sales: 1.46, cost: 1.42),
      ]);
      expect(t.soldUsd, 0.3);
      expect(t.profitLyd, 0.06);
    });
    test('a loss is negative', () {
      final t = ProfitTotals.of([_row(sold: 1000, sales: 7000, cost: 7200)]);
      expect(t.profitLyd, -200);
      expect(t.marginPerUsd, -0.2);
    });
    test('nothing sold: no rates to show', () {
      final t = ProfitTotals.of([_row(bought: 100, paid: 700)]);
      expect(t.avgSellRate, isNull);
      expect(t.marginPercent, isNull);
      expect(t.avgBuyRate, 7);
    });
    test('the cost history speaks Arabic', () {
      expect(
        CostEvent.fromJson(const {
          'kind': 'sell_cancel',
          'balance_before': 1000,
          'cost_before': 7,
          'usd_amount': 1000,
          'rate': 5,
          'balance_after': 2000,
          'cost_after': 6,
          'created_at': '2026-10-28T12:00:00Z',
        }).label,
        'إلغاء خروج',
      );
      expect(
        CostEvent.fromJson(const {
          'kind': 'buy_cancel',
          'balance_before': 2000,
          'cost_before': 7.5,
          'usd_amount': 1000,
          'rate': 8,
          'balance_after': 1000,
          'cost_after': 7,
          'created_at': '2026-10-28T12:00:00Z',
        }).label,
        'إلغاء دخول',
      );
    });
  });

  group('the screens', () {
    Future<void> pumpRate(
      WidgetTester tester, {
      required bool sell,
      required String typed,
      double usd = 1000,
      double? cost,
      double? balance,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: RateFields(
                controller: TextEditingController(text: typed),
                usd: usd,
                rates: const ExchangeRates(sell: 7.3, buy: 7.1, canEdit: true),
                sell: sell,
                enabled: true,
                onDisabledTap: () {},
                height: 48,
                textStyle: const TextStyle(fontSize: 16),
                accountCost: cost,
                accountBalance: balance,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('selling below the cost shows the loss', (tester) async {
      await pumpRate(tester, sell: true, typed: '7.0', cost: 7.2);
      expect(
        find.text('أقل من سعر التكلفة 7.2000: خسارة 200.00 د.ل'),
        findsOneWidget,
      );
    });

    testWidgets('selling above it shows the break-even only', (tester) async {
      await pumpRate(tester, sell: true, typed: '7.35', cost: 7.2);
      expect(find.text('سعر التكلفة (التعادل) 7.2000'), findsOneWidget);
    });

    testWidgets('an employee is never given a cost: no line', (tester) async {
      await pumpRate(tester, sell: true, typed: '7.0');
      expect(find.byKey(const ValueKey('cost-note')), findsNothing);
    });

    testWidgets('a buy shows the cost after it', (tester) async {
      await pumpRate(
        tester,
        sell: false,
        typed: '7.40',
        usd: 5000,
        cost: 7.10,
        balance: 10000,
      );
      expect(
        find.text('التكلفة بعد هذا الشراء: 7.1000 ← 7.2000'),
        findsOneWidget,
      );
    });

    testWidgets('a rate out of range is said so', (tester) async {
      await pumpRate(tester, sell: true, typed: '725');
      expect(find.textContaining('سعر غير معقول'), findsOneWidget);
    });

    testWidgets('the profit card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ProfitCard(
                  rows: [
                    _row(
                      sold: 3000,
                      sales: 22050,
                      cost: 21600,
                      unpriced: 1,
                      unpricedUsd: 100,
                    ),
                    _row(
                      id: 'b',
                      name: 'الصحراء',
                      sold: 1000,
                      sales: 7000,
                      cost: 7200,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('+250.00 د.ل'), findsOneWidget, reason: '450 − 200');
      expect(find.text('+450.00 د.ل'), findsOneWidget);
      expect(find.text('−200.00 د.ل'), findsOneWidget);
      expect(find.byKey(const ValueKey('profit-unpriced')), findsOneWidget);
    });
  });
}
