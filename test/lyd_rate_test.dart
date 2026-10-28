import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/exchange_rates/domain/exchange_rates.dart';
import 'package:eshary/features/exchange_rates/presentation/exchange_rates_providers.dart';
import 'package:eshary/features/exchange_rates/presentation/rate_fields.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _transferJson({
  Object? rate,
  Object? lyd,
  String? cancelledAt,
}) =>
    {
      'id': 't1',
      'owner_id': 'o',
      'company_id': 'c',
      'exchange_id': 'x',
      'beneficiary_name': 'م',
      'beneficiary_account_company': null,
      'beneficiary_code': null,
      'amount': 1000,
      'reference': 'Rh0103',
      'status': 'archived',
      'created_at': '2026-10-28T12:00:00Z',
      'archived_at': '2026-10-28T12:00:00Z',
      'created_by_employee_id': null,
      'cancelled_at': cancelledAt,
      if (rate != null) 'rate': rate,
      if (lyd != null) 'lyd_amount': lyd,
    };

Map<String, dynamic> _buyJson({Object? rate, Object? lyd}) => {
      'id': 'b1',
      'owner_id': 'o',
      'my_company_id': 'c',
      'exchange_id': 'x',
      'client_id': null,
      'client_from_account': null,
      'usd_amount': 500,
      'rate': rate,
      'lyd_amount': lyd,
      'reference': '',
      'status': 'archived',
      'created_at': '2026-10-28T12:00:00Z',
      'archived_at': '2026-10-28T12:00:00Z',
      'created_by_employee_id': null,
      'cancelled_at': null,
    };

void main() {
  group('the dinars, exactly as the database computes them (0081)', () {
    test('plain products', () {
      expect(lydFor(1000, 7.25), 7250.00);
      expect(lydFor(500, 7.05), 3525.00);
      expect(lydFor(200, 7.1235), 1424.70);
    });
    test('rounded to the dirham, half up', () {
      expect(lydFor(333.33, 7.1234), 2374.44); // 2374.442922
      expect(lydFor(0.07, 7.5), 0.53); // 0.525
      expect(lydFor(0.01, 0.5), 0.01); // 0.005
    });
    test('a rate typed with more than 4 decimals is rounded like the database',
        () {
      // 7.12345 is 7.1234499… as a double: still 7.1235, as in PostgreSQL
      expect(lydFor(100, 7.12345), 712.35);
      expect(formatRate(7.12345), '7.1235');
      expect(lydFor(999.99, 7.12345), 7123.43); // same as the database test
    });
    test('dollars typed with more than 2 decimals: the stored cent is used',
        () {
      expect(lydFor(0.125, 8), 1.04); // amount stored as 0.13
    });
    test('no binary-fraction error on large amounts', () {
      expect(lydFor(999999999.99, 9.9999), 9999899999.90);
      expect(lydFor(0.1 + 0.2, 10), 3.00);
    });
  });

  group('how a rate is shown', () {
    test('without useless zeros', () {
      expect(formatRate(7.25), '7.25');
      expect(formatRate(7), '7');
      expect(formatRate(7.1), '7.1');
      expect(formatRate(7.1235), '7.1235');
      expect(formatRate(5.0000), '5');
    });
  });

  group('a typed rate far from the last one is questioned', () {
    test('within 15% passes, beyond is questioned', () {
      expect(rateLooksWrong(7.5, 7.25), isFalse);
      expect(rateLooksWrong(72.5, 7.25), isTrue); // a misplaced point
      expect(rateLooksWrong(0.725, 7.25), isTrue);
      expect(rateLooksWrong(8.5, 7.25), isTrue);
    });
    test('with no last rate nothing is questioned', () {
      expect(rateLooksWrong(72.5, null), isFalse);
    });
  });

  group('the models', () {
    test('an exit with a rate', () {
      final t = Transfer.fromJson(_transferJson(rate: 7.25, lyd: 7250));
      expect(t.hasRate, isTrue);
      expect(t.rate, 7.25);
      expect(t.lydAmount, 7250);
      expect(t.netLyd, 7250);
    });
    test('an exit saved before 0081 (no columns, or empty)', () {
      final t = Transfer.fromJson(_transferJson());
      expect(t.hasRate, isFalse);
      expect(t.rate, isNull);
      expect(t.netLyd, 0);
    });
    test('a cancelled exit keeps its dinars but counts for none', () {
      final t = Transfer.fromJson(
        _transferJson(
          rate: 7.25,
          lyd: 7250,
          cancelledAt: '2026-10-28T13:00:00Z',
        ),
      );
      expect(t.lydAmount, 7250);
      expect(t.netLyd, 0);
    });
    test('an entry without a real rate', () {
      final b = CurrencyBuy.fromJson(_buyJson());
      expect(b.hasRate, isFalse);
      expect(b.netLyd, 0);
    });
    test('an entry with a rate', () {
      final b = CurrencyBuy.fromJson(_buyJson(rate: 7.05, lyd: 3525));
      expect(b.rate, 7.05);
      expect(b.netLyd, 3525);
    });
  });

  group('the rate an operation is saved with', () {
    final typed = TextEditingController(text: '7.3');
    test('the administrator: what was typed', () {
      const r = ExchangeRates(sell: 7.25, buy: 7.1, canEdit: true);
      expect(effectiveRate(typed, r, sell: true), 7.3);
    });
    test('an employee without the permission: the administrator\'s last rate',
        () {
      const r = ExchangeRates(sell: 7.25, buy: 7.1, canEdit: false);
      expect(effectiveRate(typed, r, sell: true), 7.25);
      expect(effectiveRate(typed, r, sell: false), 7.1);
    });
    test('…and none when the administrator has not set one', () {
      const r = ExchangeRates(sell: null, buy: null, canEdit: false);
      expect(effectiveRate(typed, r, sell: true), 0);
    });
    test('a database before 0083: one flag for both', () {
      final r = ExchangeRates.fromJson(
        const {'sell': 7.25, 'buy': null, 'can_edit': false},
      );
      expect(r.sell, 7.25);
      expect(r.buy, isNull);
      expect(r.canEditSell, isFalse);
      expect(r.canEditBuy, isFalse);
    });
    test('since 0083: one flag per kind', () {
      final r = ExchangeRates.fromJson(const {
        'sell': 7.25,
        'buy': 7.1,
        'can_edit_sell': true,
        'can_edit_buy': false,
        'can_edit': false,
      });
      expect(r.canEditFor(sell: true), isTrue);
      expect(r.canEditFor(sell: false), isFalse);
    });
    test('exit only: types the sell rate, the buy rate is the last one', () {
      const r = ExchangeRates(
        sell: 7.25,
        buy: 7.1,
        canEditSell: true,
        canEditBuy: false,
      );
      expect(effectiveRate(typed, r, sell: true), 7.3);
      expect(effectiveRate(typed, r, sell: false), 7.1);
    });
    test('entry only: types the buy rate, the sell rate is the last one', () {
      const r = ExchangeRates(
        sell: 7.25,
        buy: 7.1,
        canEditSell: false,
        canEditBuy: true,
      );
      expect(effectiveRate(typed, r, sell: true), 7.25);
      expect(effectiveRate(typed, r, sell: false), 7.3);
    });
  });

  group('the two boxes', () {
    Future<void> pump(
      WidgetTester tester, {
      required ExchangeRates rates,
      required TextEditingController controller,
      double usd = 1000,
      bool sell = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  controller.addListener(() => setState(() {}));
                  return RateFields(
                    controller: controller,
                    usd: usd,
                    rates: rates,
                    sell: sell,
                    enabled: true,
                    onDisabledTap: () {},
                    height: 48,
                    textStyle: const TextStyle(fontSize: 16),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the administrator types the rate, the dinars follow',
        (tester) async {
      final c = TextEditingController();
      await pump(
        tester,
        rates: const ExchangeRates(sell: 7.25, buy: 7.1, canEdit: true),
        controller: c,
      );
      expect(find.text('سعر البيع (د.ل لكل \$)'), findsOneWidget);
      expect(
        find.text('آخر سعر 7.25'),
        findsOneWidget,
        reason: 'a hint, not a value',
      );
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'only the rate is typed',
      );
      await tester.enterText(find.byType(TextField), '7.3');
      await tester.pump();
      expect(find.text('7,300.00'), findsOneWidget);
    });

    testWidgets('a rate far from the last one is marked', (tester) async {
      final c = TextEditingController();
      await pump(
        tester,
        rates: const ExchangeRates(sell: 7.25, buy: 7.1, canEdit: true),
        controller: c,
      );
      await tester.enterText(find.byType(TextField), '72.5');
      await tester.pump();
      expect(
        find.textContaining('يختلف كثيرًا عن آخر سعر (7.25)'),
        findsOneWidget,
      );
    });

    testWidgets('an employee without the permission sees the rate locked',
        (tester) async {
      final c = TextEditingController();
      await pump(
        tester,
        rates: const ExchangeRates(sell: 7.25, buy: 7.1, canEdit: false),
        controller: c,
      );
      expect(find.byType(TextField), findsNothing, reason: 'nothing to type');
      expect(find.text('7.25'), findsOneWidget);
      expect(find.text('7,250.00'), findsOneWidget);
      expect(find.text('سعر المدير، لا يمكن تعديله.'), findsOneWidget);
    });

    testWidgets('exit-only permission: the entry box is locked',
        (tester) async {
      const r = ExchangeRates(
        sell: 7.25,
        buy: 7.1,
        canEditSell: true,
        canEditBuy: false,
      );
      final c = TextEditingController();
      await pump(tester, rates: r, controller: c, sell: false);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('7.1'), findsOneWidget);
      expect(find.text('سعر المدير، لا يمكن تعديله.'), findsOneWidget);
      await pump(tester, rates: r, controller: c);
      expect(find.byType(TextField), findsOneWidget, reason: 'the exit box');
    });

    testWidgets('…and is told when the administrator has set none',
        (tester) async {
      final c = TextEditingController();
      await pump(
        tester,
        rates: const ExchangeRates(sell: null, buy: null, canEdit: false),
        controller: c,
        sell: false,
      );
      expect(find.text('سعر الشراء (د.ل لكل \$)'), findsOneWidget);
      expect(
        find.text('لم يحدد المدير سعر الشراء بعد. تواصل مع المدير.'),
        findsOneWidget,
      );
    });
  });
}
