import 'package:eshary/core/theme.dart';
import 'package:eshary/features/customers/data/customers_repository.dart';
import 'package:eshary/features/customers/domain/customer_account.dart';
import 'package:eshary/features/customers/presentation/customer_statement_screen.dart';
import 'package:eshary/features/exchange_rates/presentation/lyd_method_selector.dart';
import 'package:eshary/shared/formatters.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 29, 9);

Map<String, dynamic> _statementJson() => {
      'opening': 100,
      'closing': 620,
      'entries': [
        {
          'id': 'e1',
          'kind': 'sale',
          'amount': 700,
          'created_at': '2026-10-29T08:00:00Z',
          'reference': 'Rh0101',
          'usd': 100,
          'rate': 7,
          'lyd': 700,
        },
        {
          'id': 'e2',
          'kind': 'collect',
          'amount': -400,
          'pocket': 'cash',
          'note': 'دفعة',
          'created_at': '2026-10-29T10:00:00Z',
        },
        {
          'id': 'e3',
          'kind': 'opening',
          'amount': 220,
          'created_at': '2026-10-29T11:00:00Z',
        },
      ],
    };

class _FakeRepo implements CustomersRepository {
  final calls = <String>[];

  @override
  Future<CustomerStatement> statement(
    String clientId,
    DateTime from,
    DateTime to, {
    String? book,
  }) async =>
      CustomerStatement.fromJson(_statementJson());

  @override
  Future<double> addEntry({
    required String clientId,
    required String kind,
    required double amount,
    String? pocket,
    String? note,
    String? requestId,
    String? book,
  }) async {
    calls.add('$kind $amount $pocket $book');
    return 0;
  }

  @override
  Future<void> setLimit(String clientId, double? limit) async =>
      calls.add('limit $limit');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('what a save sends for the payment chosen', () {
    test('cash / bank: all of it, through that pocket, in that book', () {
      expect(
        lydPaymentArgs(kLydCash),
        (method: kLydCash, paid: null, book: kLydCash),
      );
      expect(
        lydPaymentArgs(kLydBank),
        (method: kLydBank, paid: null, book: kLydBank),
      );
    });
    test('credit: nothing paid, no pocket, in the book chosen', () {
      expect(
        lydPaymentArgs(kLydCredit, pocket: kLydBank),
        (method: null, paid: 0.0, book: kLydBank),
      );
    });
    test('partial: the part paid, through its pocket, in that book', () {
      expect(
        lydPaymentArgs(kLydPartial, partialPaid: 250, pocket: kLydBank),
        (method: kLydBank, paid: 250.0, book: kLydBank),
      );
    });
    test('the book of each choice (0093)', () {
      expect(lydBookOf(kLydCash, kLydBank), kLydCash);
      expect(lydBookOf(kLydBank, kLydCash), kLydBank);
      expect(lydBookOf(kLydCredit, kLydBank), kLydBank);
      expect(lydBookOf(kLydPartial, kLydCash), kLydCash);
    });
    test('which choices leave a debt', () {
      expect(lydOnCredit(kLydCash), isFalse);
      expect(lydOnCredit(kLydCredit), isTrue);
      expect(lydOnCredit(kLydPartial), isTrue);
      expect(lydMethodLabel(kLydCredit), 'آجل');
    });
  });

  group('the customers\' accounts', () {
    test('a statement\'s running balance, in cents', () {
      final s = CustomerStatement.fromJson(_statementJson());
      expect(s.running, [800, 400, 620]);
      expect(s.entries[1].label, 'تحصيل منه');
      expect(s.entries.first.reference, 'Rh0101');
    });
    test('owed to us and owed by us, apart', () {
      CustomerBalance c(double b) =>
          CustomerBalance(clientId: '$b', name: 'x', balance: b);
      final t = CustomerTotals.of([c(500), c(-255), c(0.1), c(-0.2)]);
      expect(t.receivable, 500.1);
      expect(t.payable, 255.2);
    });
    test('the balance in words', () {
      expect(customerBalanceLabel(500, formatMoney), 'لنا 500.00 د.ل');
      expect(customerBalanceLabel(-255, formatMoney), 'علينا 255.00 د.ل');
      expect(customerBalanceLabel(0.001, formatMoney), 'مسدَّد');
    });
    test('over the limit', () {
      expect(
        const CustomerBalance(
          clientId: 'c',
          name: 'x',
          balance: 900,
          creditLimit: 800,
        ).overLimit,
        isTrue,
      );
      expect(
        const CustomerBalance(clientId: 'c', name: 'x', balance: -900)
            .overLimit,
        isFalse,
      );
    });
  });

  group('the payment selector', () {
    Future<void> pump(
      WidgetTester tester,
      String value, {
      bool credit = true,
      TextEditingController? paid,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 360,
                child: LydMethodSelector(
                  value: value,
                  sell: true,
                  onChanged: (_) {},
                  allowCredit: credit,
                  paidController: paid,
                  onPocketChanged: (_) {},
                  total: 700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('without credit: two choices, as before', (tester) async {
      await pump(tester, kLydCash, credit: false);
      expect(find.text('آجل'), findsNothing);
      expect(find.text('جزئي'), findsNothing);
    });
    testWidgets('credit: all of it stays on the customer', (tester) async {
      await pump(tester, kLydCredit);
      expect(find.text('آجل'), findsOneWidget);
      expect(find.text('يبقى على العميل: 700.00 د.ل'), findsOneWidget);
      expect(find.byKey(const ValueKey('lyd-paid')), findsNothing);
    });
    testWidgets('partial: the part paid, and the rest shown', (tester) async {
      await pump(
        tester,
        kLydPartial,
        paid: TextEditingController(text: '250'),
      );
      expect(find.byKey(const ValueKey('lyd-paid')), findsOneWidget);
      expect(find.text('يبقى على العميل: 450.00 د.ل'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a customer\'s statement screen', () {
    Future<_FakeRepo> open(WidgetTester tester) async {
      final repo = _FakeRepo();
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [customersRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: CustomerStatementScreen(
                clientId: 'c1',
                title: 'محمد / السيادة',
                creditLimit: 1000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('the balance, the limit and each line', (tester) async {
      await open(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('customer-balance')))
            .data,
        'لنا 620.00 د.ل',
      );
      expect(find.text('حد الدين 1,000.00 د.ل'), findsOneWidget);
      expect(find.textContaining('بيع بالآجل · Rh0101'), findsOneWidget);
      expect(find.textContaining('تحصيل منه'), findsWidgets);
    });

    testWidgets('a collection into the box', (tester) async {
      final repo = await open(tester);
      await tester.tap(find.byKey(const ValueKey('customer-collect')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customer-amount')),
        '400',
      );
      await tester.tap(find.byKey(const ValueKey('customer-amount-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['collect 400.0 cash cash']);
    });

    testWidgets('an opening balance we owe him is negative', (tester) async {
      final repo = await open(tester);
      await tester.tap(find.byKey(const ValueKey('customer-opening')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('علينا له'));
      await tester.enterText(
        find.byKey(const ValueKey('customer-amount')),
        '120',
      );
      await tester.tap(find.byKey(const ValueKey('customer-amount-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['opening -120.0 null cash']);
    });

    testWidgets('the limit, and none at all', (tester) async {
      final repo = await open(tester);
      await tester.tap(find.byKey(const ValueKey('customer-limit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customer-limit-value')),
        '',
      );
      await tester.tap(find.byKey(const ValueKey('customer-limit-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['limit null']);
      expect(find.text('بلا حد دين: لا بيع بالآجل له'), findsOneWidget);
    });

    testWidgets('a 320 phone: nothing overflows', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1200));
      await open(tester);
      expect(tester.takeException(), isNull);
    });
  });

  test('the statement prints', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildCustomerStatement(
      customer: 'محمد / السيادة',
      creditLimit: 1000,
      statement: CustomerStatement.fromJson(_statementJson()),
      start: _t0,
      end: _t0.add(const Duration(hours: 12)),
      exportedBy: 'المدير',
    );
    expect(bytes.length, greaterThan(1000));
  });
}
