import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/domain/account_statement.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/account_statement_providers.dart';
import 'package:eshary/features/companies/presentation/account_statement_screen.dart';
import 'package:eshary/features/companies/presentation/accounts_screen.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buys_providers.dart';
import 'package:eshary/features/employee_auth/data/employee_auth_repository.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/sub_users/domain/sub_user.dart';
import 'package:eshary/features/sub_users/presentation/sub_users_providers.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 10, 8);
DateTime _at(int hour, [int minute = 0]) =>
    DateTime(2026, 10, 8, hour, minute);

CurrencyBuy _buy(String id, double usd, DateTime at,
        {String? by, String exchange = 'e1'}) =>
    CurrencyBuy(
      id: id,
      ownerId: 'o',
      myCompanyId: 'c1',
      exchangeId: exchange,
      clientId: null,
      clientFromAccount: null,
      usdAmount: usd,
      rate: 1,
      lydAmount: usd,
      reference: id,
      status: CurrencyBuyStatus.archived,
      createdAt: at,
      archivedAt: at,
      createdByEmployeeId: by,
    );

Transfer _out(String id, double amount, DateTime at,
        {String? by, String exchange = 'e1'}) =>
    Transfer(
      id: id,
      ownerId: 'o',
      companyId: 'c1',
      exchangeId: exchange,
      beneficiaryName: 'م',
      beneficiaryAccountCompany: null,
      beneficiaryCode: null,
      amount: amount,
      reference: id,
      status: TransferStatus.archived,
      createdAt: at,
      archivedAt: at,
      createdByEmployeeId: by,
    );

void main() {
  group('the statement (دخول / خروج / الرصيد)', () {
    // admin: +1000 (9:00) −350 (10:00); Sami: +200 (11:00) −50 (12:00);
    // Omar: −75 (13:00); another account e2: +40 (14:00) by Sami.
    final buys = [
      _buy('b1', 1000, _at(9)),
      _buy('b2', 200, _at(11), by: 'sami'),
      _buy('b3', 40, _at(14), by: 'sami', exchange: 'e2'),
    ];
    final transfers = [
      _out('t1', 350, _at(10)),
      _out('t2', 50, _at(12), by: 'sami'),
      _out('t3', 75, _at(13), by: 'omar'),
    ];
    AccountStatement run({
      StatementScope scope = StatementScope.all,
      String? employeeId,
      String? exchangeId,
      DateTime? start,
      DateTime? end,
    }) =>
        buildAccountStatement(
          buys: buys,
          transfers: transfers,
          start: start ?? _day,
          end: end ?? DateTime(2026, 10, 8, 23, 59, 59),
          scope: scope,
          employeeId: employeeId,
          exchangeId: exchangeId,
        );

    test('الكل: everyone, oldest first, balance running', () {
      final s = run();
      expect(s.entries.length, 6);
      expect(s.entries.map((e) => e.at.hour), [9, 10, 11, 12, 13, 14]);
      // +1000, −350, +200, −50, −75, +40
      expect(s.entries.map((e) => e.balance), [1000, 650, 850, 800, 725, 765]);
      expect(s.totalIncome, 1240);
      expect(s.totalOutgoing, 475);
      expect(s.balance, 765);
    });

    test('the accountant example: دخول 1000, خروج 350 → الرصيد 650', () {
      final s = run(scope: StatementScope.me);
      expect(s.entries.map((e) => (e.income, e.outgoing, e.balance)),
          [(1000.0, null, 1000.0), (null, 350.0, 650.0)]);
    });

    test('أنا: only what the admin did (no employee)', () {
      final s = run(scope: StatementScope.me);
      expect(s.entries.every((e) => e.employeeId == null), isTrue);
      expect(s.totalIncome, 1000);
      expect(s.totalOutgoing, 350);
      expect(s.balance, 650);
    });

    test('موظف: only that employee, with their own running balance', () {
      final s = run(scope: StatementScope.employee, employeeId: 'sami');
      expect(s.entries.length, 3);
      expect(s.entries.every((e) => e.employeeId == 'sami'), isTrue);
      expect(s.entries.map((e) => e.balance), [200, 150, 190]);
      final omar = run(scope: StatementScope.employee, employeeId: 'omar');
      expect(omar.totalOutgoing, 75);
      expect(omar.balance, -75);
    });

    test('an employee scope without an id shows nothing, not everyone', () {
      expect(run(scope: StatementScope.employee).isEmpty, isTrue);
    });

    test('one account only', () {
      final s = run(exchangeId: 'e2');
      expect(s.entries.length, 1);
      expect(s.balance, 40);
      expect(run(exchangeId: 'e1').entries.length, 5);
    });

    test('the period bounds are respected', () {
      final s = run(start: _at(10), end: _at(12, 30));
      expect(s.entries.map((e) => e.at.hour), [10, 11, 12]);
      expect(s.balance, -350 + 200 - 50);
      expect(run(start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 9, 23)).isEmpty,
          isTrue);
    });

    test('a row is counted once, by its posting time', () {
      final late = CurrencyBuy(
        id: 'x',
        ownerId: 'o',
        myCompanyId: 'c1',
        exchangeId: 'e1',
        clientId: null,
        clientFromAccount: null,
        usdAmount: 5,
        rate: 1,
        lydAmount: 5,
        reference: 'x',
        status: CurrencyBuyStatus.archived,
        createdAt: _at(8),
        archivedAt: _at(20),
        createdByEmployeeId: null,
      );
      final s = buildAccountStatement(
        buys: [late],
        transfers: const [],
        start: _at(19),
        end: _at(21),
      );
      expect(s.entries.length, 1);
      expect(s.entries.single.at.hour, 20);
    });

    test('empty input', () {
      final s = buildAccountStatement(
        buys: const [],
        transfers: const [],
        start: _day,
        end: _day,
      );
      expect(s.isEmpty, isTrue);
      expect(s.balance, 0);
    });
  });

  // ------------------------------------------------------------- the screen
  group('the screen', () {
    final t0 = DateTime(2026, 1, 1);
    final company = Company(
      id: 'c1',
      ownerId: 'o',
      name: 'حسابي الرئيسي',
      startRef: 'A1',
      createdAt: t0,
    );
    Exchange exchange(String id, String name) => Exchange(
          id: id,
          companyId: 'c1',
          name: name,
          balance: 100,
          ourCode: 'X',
          country: null,
          createdAt: t0,
        );
    SubUser employee(String id, String name) => SubUser(
          id: id,
          parentAdminId: 'a',
          employeeName: name,
          phoneNumber: '0911110000',
          loginCodeUsed: true,
          permissions: const [],
          status: SubUserStatus.active,
          deviceId: null,
          branchId: null,
          lastLoginAt: null,
          createdAt: t0,
        );

    // today, so "اليوم" (the default period) covers them
    final now = DateTime.now();
    DateTime today(int h) => DateTime(now.year, now.month, now.day, h);
    final data = (
      buys: [
        _buy('b1', 1000, today(9)),
        _buy('b2', 200, today(11), by: 'sami'),
      ],
      transfers: [
        _out('t1', 350, today(10)),
        _out('t2', 75, today(13), by: 'omar'),
      ],
    );

    Future<void> open(WidgetTester tester) async {
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
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statementDataProvider.overrideWith((ref, range) async => data),
            subUsersListProvider.overrideWith(
              (ref) async => [employee('sami', 'سامي'), employee('omar', 'عمر')],
            ),
            allExchangesProvider.overrideWith(
              (ref) async => [exchange('e1', 'صرافة أ'), exchange('e2', 'صرافة ب')],
            ),
            companiesListProvider.overrideWith((ref) async => [company]),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            themeMode: ThemeMode.dark,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: AccountStatementScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('الكل by default: the three columns and everyone\'s totals',
        (tester) async {
      await open(tester);
      expect(find.text('دخول'), findsOneWidget);
      expect(find.text('خروج'), findsOneWidget);
      expect(find.text('الرصيد'), findsWidgets);
      expect(find.text('+\$1,200.00'), findsOneWidget, reason: 'إجمالي الدخول');
      expect(find.text('-\$425.00'), findsOneWidget, reason: 'إجمالي الخروج');
      expect(find.text('\$775.00'), findsOneWidget, reason: 'الرصيد');
    });

    testWidgets('أنا: only the admin\'s operations', (tester) async {
      await open(tester);
      await tester.tap(find.text('أنا'));
      await tester.pumpAndSettle();
      expect(find.text('+\$1,000.00'), findsOneWidget);
      expect(find.text('-\$350.00'), findsOneWidget);
      expect(find.text('\$650.00'), findsOneWidget);
    });

    testWidgets('موظف: pick an employee to see theirs', (tester) async {
      await open(tester);
      await tester.tap(find.text('موظف'));
      await tester.pumpAndSettle();
      // the first employee (سامي) is selected: one entry of 200
      expect(find.text('+\$200.00'), findsOneWidget);
      expect(find.text('-\$0.00'), findsOneWidget);
      // switch to عمر: one exit of 75
      await tester.tap(find.text('سامي').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عمر').last);
      await tester.pumpAndSettle();
      // إجمالي الخروج and الرصيد both read -$75.00
      expect(find.text('-\$75.00'), findsNWidgets(2));
    });

    testWidgets('has a PDF button', (tester) async {
      await open(tester);
      expect(find.byTooltip('تصدير PDF'), findsOneWidget);
    });
  });

  // ------------------------------------------- the button in "حساباتي"
  group('the button in the accounts tab', () {
    final t0 = DateTime(2026, 1, 1);

    Future<void> open(WidgetTester tester, EmployeeIdentity? identity) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentEmployeeProvider.overrideWith((ref) async => identity),
            companiesListProvider.overrideWith(
              (ref) async => [
                Company(
                  id: 'c1',
                  ownerId: 'o',
                  name: 'ش',
                  startRef: 'A1',
                  createdAt: t0,
                ),
              ],
            ),
            allExchangesProvider.overrideWith(
              (ref) async => [
                Exchange(
                  id: 'e1',
                  companyId: 'c1',
                  name: 'صرافة',
                  balance: 100,
                  ourCode: 'X',
                  country: null,
                  createdAt: t0,
                ),
              ],
            ),
            exchangeCompaniesListProvider.overrideWith(
              (ref) async => [
                ExchangeCompany(
                  id: 'x1',
                  ownerId: 'o',
                  name: 'صرافة',
                  createdAt: t0,
                ),
              ],
            ),
            archivedBuysProvider.overrideWith(
              (ref) async => [_buy('b', 5, t0)],
            ),
            archivedTransfersProvider
                .overrideWith((ref) async => const <Transfer>[]),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            themeMode: ThemeMode.dark,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: AccountsScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the admin sees "كشف حساب" and it opens the statement',
        (tester) async {
      await open(tester, null);
      expect(find.text('كشف حساب'), findsOneWidget);
    });

    testWidgets('an employee with the full account does not', (tester) async {
      await open(
        tester,
        const EmployeeIdentity(
          sessionId: 's',
          subUserId: 'u',
          parentAdminId: 'a',
          employeeName: 'رافع',
          permissions: ['accounts_all'],
          branchId: null,
        ),
      );
      expect(find.text('كشف حساب'), findsNothing);
    });
  });
}
