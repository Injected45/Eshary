import 'package:eshary/core/theme.dart';
import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/clients/presentation/clients_providers.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buy_screen.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buys_providers.dart';
import 'package:eshary/features/employee_auth/data/employee_auth_repository.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 1, 1);

Company _company(String id) => Company(
      id: id,
      ownerId: 'o',
      name: 'حساب $id',
      startRef: 'A1',
      createdAt: _t0,
    );

Exchange _exchange(String id, String name, String code) => Exchange(
      id: id,
      companyId: 'c$id',
      name: name,
      balance: 1000,
      ourCode: code,
      country: null,
      createdAt: _t0,
    );

ExchangeCompany _ec(String name) =>
    ExchangeCompany(id: name, ownerId: 'o', name: name, createdAt: _t0);

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
  EmployeeIdentity? identity,
}) async {
  await _loadFonts();
  await tester.binding.setSurfaceSize(const Size(400, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentEmployeeProvider.overrideWith((ref) async => identity),
        allExchangesProvider.overrideWith((ref) async => exchanges),
        companiesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _company(e.companyId)],
        ),
        exchangeCompaniesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _ec(e.name)],
        ),
        clientsListProvider.overrideWith((ref) async => const <Client>[]),
        dailyBuysProvider.overrideWith((ref) async => const <CurrencyBuy>[]),
        pendingBuysProvider.overrideWith((ref) async => const <CurrencyBuy>[]),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: CurrencyBuyScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const blocked = 'عذراً لا يمكن فتح الجهة المرسلة';
  const senderMarker = 'الشركة المرسلة'; // a field inside the sender section
  final one = [_exchange('1', 'شركة الصرافة', 'X-100')];
  final two = [
    _exchange('1', 'شركة أ', 'X-100'),
    _exchange('2', 'شركة ب', 'X-200'),
  ];

  testWidgets('one account: filled in and the sender section opens at once',
      (tester) async {
    await _open(tester, one);
    expect(find.text(senderMarker), findsOneWidget, reason: 'sender open');
    // The account section is folded; opening it shows everything filled in.
    await tester.tap(find.text('دخول لحسابي'));
    await tester.pumpAndSettle();
    expect(find.text('X-100'), findsOneWidget, reason: 'account code');
    expect(find.text('شركة الصرافة'), findsWidgets, reason: 'company');
  });

  testWidgets('several accounts: nothing chosen, sender section is locked',
      (tester) async {
    await _open(tester, two);
    expect(find.text('X-100'), findsNothing);
    expect(find.text(senderMarker), findsNothing);
    await tester.tap(find.text('الجهة المرسلة'));
    await tester.pumpAndSettle();
    expect(find.textContaining(blocked), findsOneWidget);
    expect(find.textContaining('عليك استكمال بيانات حسابك أولاً'),
        findsOneWidget);
    expect(find.text(senderMarker), findsNothing);
  });

  testWidgets('employee app: same behaviour', (tester) async {
    const rafe = EmployeeIdentity(
      sessionId: 's',
      subUserId: 'u',
      parentAdminId: 'a',
      employeeName: 'رافع',
      permissions: ['buys_create'],
      branchId: null,
    );
    await _open(tester, one, identity: rafe);
    expect(find.text(senderMarker), findsOneWidget);
    await tester.tap(find.text('دخول لحسابي'));
    await tester.pumpAndSettle();
    expect(find.text('X-100'), findsOneWidget);
  });
}
