import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/data/companies_repository.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/employee_auth/data/employee_auth_repository.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/transfers/data/transfers_repository.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:eshary/features/transfers/presentation/transfers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCompaniesRepo implements CompaniesRepository {
  @override
  Future<String> nextReference(String companyId) async => 'REF-0001';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _t0 = DateTime(2026, 1, 1);

Company _company(String id) => Company(
      id: id,
      ownerId: 'o',
      name: 'شركة $id',
      startRef: 'A1',
      createdAt: _t0,
    );

Exchange _exchange(String id, String name, String code, double balance) =>
    Exchange(
      id: id,
      companyId: 'c$id',
      name: name,
      balance: balance,
      ourCode: code,
      country: null,
      createdAt: _t0,
    );

ExchangeCompany _ec(String name) =>
    ExchangeCompany(id: name, ownerId: 'o', name: name, createdAt: _t0);

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

Future<void> _open(
  WidgetTester tester,
  List<Exchange> exchanges, {
  double width = 400,
  EmployeeIdentity? identity,
  Map<String, ExchangeBalance> balances = const {},
}) async {
  await _loadFonts();
  await tester.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allExchangesProvider.overrideWith((ref) async => exchanges),
        companiesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _company(e.companyId)],
        ),
        exchangeCompaniesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _ec(e.name)],
        ),
        currentEmployeeProvider.overrideWith((ref) async => identity),
        exchangeBalancesProvider.overrideWith((ref) async => balances),
        dailyTransfersProvider.overrideWith((ref) async => const <Transfer>[]),
        companiesRepositoryProvider.overrideWithValue(_FakeCompaniesRepo()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: TransfersScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one account: everything is filled in, only the amount is left',
      (tester) async {
    await _open(tester, [_exchange('1', 'شركة الصرافة', 'X-100', 2500)]);
    expect(find.text('X-100'), findsOneWidget, reason: 'account code');
    expect(find.text('2,500.00'), findsOneWidget, reason: 'balance');
    expect(find.text('REF-0001'), findsOneWidget, reason: 'reference');
  });

  testWidgets('several accounts: nothing is chosen for me', (tester) async {
    await _open(tester, [
      _exchange('1', 'شركة أ', 'X-100', 2500),
      _exchange('2', 'شركة ب', 'X-200', 900),
    ]);
    expect(find.text('X-100'), findsNothing);
    expect(find.text('X-200'), findsNothing);
    expect(find.text('REF-0001'), findsNothing);
  });

  testWidgets('balance + code share a row, reference + amount share a row',
      (tester) async {
    await _open(tester, [_exchange('1', 'شركة الصرافة', 'X-100', 2500)]);
    double dy(String label) => tester.getCenter(find.text(label)).dy;
    double dx(String label) => tester.getCenter(find.text(label)).dx;

    expect(dy('الرصيد المتاح'), dy('كود الحساب'));
    expect(dy('الرقم الإشاري'), dy('القيمة بالدولار (USD)'));
    expect(dy('الرقم الإشاري'), greaterThan(dy('الرصيد المتاح')));
    // Right-to-left: the first field sits on the right.
    expect(dx('الرصيد المتاح'), greaterThan(dx('كود الحساب')));
    expect(dx('الرقم الإشاري'), greaterThan(dx('القيمة بالدولار (USD)')));
  });

  testWidgets('narrow phone + amount over the balance: no overflow, error shown',
      (tester) async {
    await _open(
      tester,
      [_exchange('1', 'شركة الصرافة', 'X-100', 2500)],
      width: 360,
    );
    await tester.enterText(find.widgetWithText(TextField, ''), '99999');
    await tester.pumpAndSettle();
    expect(find.text('يتجاوز الرصيد المتاح'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('beneficiary section is locked until the transfer data is complete', () {
    const blocked = 'عذراً لا يمكن فتح الجهة المستفيدة';
    final one = [_exchange('1', 'شركة الصرافة', 'X-100', 2500)];

    testWidgets('empty amount: tapping it shows the message and stays closed',
        (tester) async {
      await _open(tester, one);
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.textContaining(blocked), findsOneWidget);
      expect(find.textContaining('عليك استكمال بيانات الحوالة أولاً'),
          findsOneWidget);
      expect(find.text('الجهات المحفوظة'), findsNothing);
    });

    testWidgets('several accounts, nothing chosen: locked', (tester) async {
      await _open(tester, [
        _exchange('1', 'شركة أ', 'X-100', 2500),
        _exchange('2', 'شركة ب', 'X-200', 900),
      ]);
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.textContaining(blocked), findsOneWidget);
      expect(find.text('الجهات المحفوظة'), findsNothing);
    });

    testWidgets('amount above the account balance: locked, says why',
        (tester) async {
      await _open(tester, one);
      await tester.enterText(find.widgetWithText(TextField, ''), '99999');
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.textContaining(blocked), findsOneWidget);
      expect(find.textContaining('يتجاوز الرصيد المتاح'), findsWidgets);
      expect(find.text('الجهات المحفوظة'), findsNothing);
    });

    testWidgets('everything filled and covered by the balance: it opens',
        (tester) async {
      await _open(tester, one);
      await tester.enterText(find.widgetWithText(TextField, ''), '100');
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.textContaining(blocked), findsNothing);
      expect(find.text('الجهات المحفوظة'), findsOneWidget);
    });
  });

  testWidgets(
    'an employee allowed to execute exits sees the account balance',
    (tester) async {
      await _open(
        tester,
        [_exchange('1', 'شركة الصرافة', 'X-100', 2500)],
        identity: const EmployeeIdentity(
          sessionId: 's',
          subUserId: 'u',
          parentAdminId: 'a',
          employeeName: 'رافع',
          permissions: ['transfers_create'],
          branchId: null,
        ),
      );
      expect(find.text('2,500.00'), findsOneWidget);
      expect(find.text('X-100'), findsOneWidget);
    },
  );

  group('available balance = account balance minus the open exits of the day', () {
    final one = [_exchange('1', 'شركة الصرافة', 'X-100', 1000)];
    // Rafe already sent 900 today: balance 1000, open 900, available 100.
    const open = {
      '1': ExchangeBalance(balance: 1000, openOut: 900, available: 100),
    };

    testWidgets('shows the available figure and explains the difference',
        (tester) async {
      await _open(tester, one, balances: open);
      expect(find.text('100.00'), findsOneWidget, reason: 'available');
      expect(find.text('1,000.00'), findsNothing, reason: 'not the raw balance');
      expect(find.textContaining('حوالات اليوم غير المقفلة'), findsOneWidget);
    });

    testWidgets('an amount above the available (but under the balance) is locked',
        (tester) async {
      await _open(tester, one, balances: open);
      await tester.enterText(find.widgetWithText(TextField, ''), '500');
      await tester.pumpAndSettle();
      expect(find.text('يتجاوز الرصيد المتاح'), findsOneWidget);
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.textContaining('المبلغ يتجاوز الرصيد المتاح'), findsWidgets);
      expect(find.text('الجهات المحفوظة'), findsNothing);
    });

    testWidgets('an amount within the available opens the beneficiary section',
        (tester) async {
      await _open(tester, one, balances: open);
      await tester.enterText(find.widgetWithText(TextField, ''), '100');
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المستفيدة'));
      await tester.pumpAndSettle();
      expect(find.text('الجهات المحفوظة'), findsOneWidget);
    });

    testWidgets('without server figures it falls back to the plain balance',
        (tester) async {
      await _open(tester, one);
      expect(find.text('1,000.00'), findsOneWidget);
      expect(find.textContaining('حوالات اليوم غير المقفلة'), findsNothing);
    });
  });
}
