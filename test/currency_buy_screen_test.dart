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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
  List<Client> clients = const <Client>[],
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
        clientsListProvider.overrideWith((ref) async => clients),
        dailyBuysProvider.overrideWith((ref) async => const <CurrencyBuy>[]),
        pendingBuysProvider.overrideWith((ref) async => const <CurrencyBuy>[]),
        todayBuysProvider.overrideWith((ref) async => const <CurrencyBuy>[]),
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

  testWidgets('one account: every container stays closed until tapped',
      (tester) async {
    await _open(tester, one);
    expect(find.text(senderMarker), findsNothing, reason: 'sender closed');
    expect(find.text('X-100'), findsNothing, reason: 'account closed');
    // opening the sender container
    await tester.tap(find.text('الجهة المرسلة'));
    await tester.pumpAndSettle();
    expect(find.text(senderMarker), findsOneWidget, reason: 'sender open');
    // and the account container shows everything filled in
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
    expect(
        find.textContaining('عليك استكمال بيانات حسابك أولاً'), findsOneWidget);
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
    expect(find.text(senderMarker), findsNothing);
    await tester.tap(find.text('الجهة المرسلة'));
    await tester.pumpAndSettle();
    expect(find.text(senderMarker), findsOneWidget);
    await tester.tap(find.text('دخول لحسابي'));
    await tester.pumpAndSettle();
    expect(find.text('X-100'), findsOneWidget);
  });

  testWidgets('no daily-close button on the entry screen', (tester) async {
    await _open(tester, one);
    expect(find.textContaining('الإقفال اليومي'), findsNothing);
    expect(find.textContaining('ترحيل'), findsNothing);
  });

  testWidgets('reference and value: one row, two identical centred boxes',
      (tester) async {
    await _open(tester, one);
    // the reference and value live in the sender container: open it
    await tester.tap(find.text('الجهة المرسلة'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    final n = tester.widgetList(fields).length;
    final reference = fields.at(n - 2);
    final value = fields.at(n - 1);

    final r = tester.getRect(reference);
    final v = tester.getRect(value);
    expect(r.top, v.top, reason: 'same row');
    expect(r.height, v.height, reason: 'same height');
    expect((r.width - v.width).abs(), lessThan(0.5), reason: 'same width');
    expect(r.height, 48);
    // right-to-left: the reference is the right one, the value the left one
    expect(r.center.dx, greaterThan(v.center.dx));
    // evenly placed: the two boxes are mirror images about the screen middle
    final gapSides = ((r.left + r.right) / 2) + ((v.left + v.right) / 2);
    expect((gapSides / 2 - 200).abs(), lessThan(1), reason: 'centred');
    // the labels sit over their boxes on the same line
    expect(tester.getCenter(find.text('الرقم الإشاري')).dy,
        tester.getCenter(find.text(r'القيمة $')).dy);

    // no icons squeezing either box
    expect(find.descendant(of: reference, matching: find.byType(FaIcon)),
        findsNothing);
    expect(find.descendant(of: value, matching: find.byType(FaIcon)),
        findsNothing);

    // the hint is the short word, centred in the box
    expect(find.text('الإشاري (اختياري)'), findsOneWidget);
    expect(find.text('أدخل الرقم الإشاري'), findsNothing);
    expect(
        (tester.getCenter(find.text('الإشاري (اختياري)')).dx - r.center.dx)
            .abs(),
        lessThan(2));
    expect(
        (tester.getCenter(find.text('الإشاري (اختياري)')).dy - r.center.dy)
            .abs(),
        lessThan(2));

    // typed text is centred
    await tester.enterText(value, '250');
    await tester.pumpAndSettle();
    expect((tester.getCenter(find.text('250')).dx - v.center.dx).abs(),
        lessThan(2));
  });

  group('containers close by hand only, and the save button', () {
    final client = Client(
      id: 'c1',
      ownerId: 'o',
      name: 'أحمد',
      company: 'شركة المرسل',
      code: 'S-1',
      createdAt: DateTime(2026, 1, 1),
    );
    const pause = Duration(milliseconds: 1500);
    FilledButton save(WidgetTester t) =>
        t.widget<FilledButton>(find.byKey(const ValueKey('save-buy')));

    testWidgets(
        'a sender with no company: "بدون شركة" lists it and the entry can be saved',
        (tester) async {
      final noCompany = Client(
        id: 'c4',
        ownerId: 'o',
        name: 'ابوبكر',
        company: null,
        code: '7001',
        createdAt: DateTime(2026, 1, 1),
      );
      await _open(tester, one, clients: [noCompany]);
      await tester.tap(find.text('دخول لحسابي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      // the company list offers "بدون شركة" because a saved sender has none
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('بدون شركة'), findsWidgets);
      await tester.tap(find.text('بدون شركة').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ابوبكر').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final n = tester.widgetList(fields).length;
      await tester.enterText(fields.at(n - 2), 'R-1');
      await tester.enterText(fields.at(n - 1), '250');
      await tester.pump();
      await tester.pump(pause);
      await tester.pumpAndSettle();
      expect(save(tester).onPressed, isNotNull, reason: 'no company needed');
    });

    testWidgets('no reference at all: the save button still works',
        (tester) async {
      await _open(tester, one, clients: [client]);
      await tester.tap(find.text('دخول لحسابي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة المرسل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أحمد').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final n = tester.widgetList(fields).length;
      // only the value: the reference box stays empty
      await tester.enterText(fields.at(n - 1), '250');
      await tester.pump();
      await tester.pump(pause);
      await tester.pumpAndSettle();
      expect(save(tester).onPressed, isNotNull,
          reason: 'a reference is optional');
      expect(find.text('الإشاري (اختياري)'), findsWidgets,
          reason: 'the box says it is optional');
    });

    testWidgets(
        'a saved sender with no code can be saved: the code is optional',
        (tester) async {
      final noCode = Client(
        id: 'c3',
        ownerId: 'o',
        name: 'تاجر بلا كود',
        company: 'شركة المرسل',
        code: null,
        createdAt: DateTime(2026, 1, 1),
      );
      await _open(tester, one, clients: [noCode]);
      await tester.tap(find.text('دخول لحسابي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة المرسل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تاجر بلا كود').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final n = tester.widgetList(fields).length;
      // only the reference and the value: no code typed
      await tester.enterText(fields.at(n - 2), 'R-1');
      await tester.enterText(fields.at(n - 1), '250');
      await tester.pump();
      await tester.pump(pause);
      await tester.pumpAndSettle();
      expect(save(tester).onPressed, isNotNull, reason: 'no code needed');
    });

    testWidgets('a sender with fixed letters shows them in the reference field',
        (tester) async {
      final trc = Client(
        id: 'c2',
        ownerId: 'o',
        name: 'تاجر',
        company: 'شركة المرسل',
        code: 'S-2',
        createdAt: DateTime(2026, 1, 1),
        refPrefix: 'TRC',
      );
      await _open(tester, one, clients: [client, trc]);
      await tester.tap(find.text('دخول لحسابي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة المرسل').last);
      await tester.pumpAndSettle();

      // a sender without letters: the plain field
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أحمد').last);
      await tester.pumpAndSettle();
      expect(find.text('TRC'), findsNothing);
      expect(find.byKey(const ValueKey('ref-prefix-edit')), findsOneWidget,
          reason: 'the pencil is there to add letters to this sender');
      expect(find.text('الإشاري (اختياري)'), findsWidgets);

      // a sender with letters: they stay in front, the number is typed
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تاجر').last);
      await tester.pumpAndSettle();
      expect(find.text('TRC'), findsOneWidget);
      // and a pencil beside the label opens the sender to change them
      expect(find.byKey(const ValueKey('ref-prefix-edit')), findsOneWidget);
    });

    testWidgets('the save button is dim until everything is filled',
        (tester) async {
      await _open(tester, one, clients: [client]);
      expect(save(tester).onPressed, isNull);
    });

    testWidgets(
        'nothing opens or closes by itself: the containers move only when tapped',
        (tester) async {
      await _open(tester, one, clients: [client]);
      await tester.tap(find.text('دخول لحسابي'));
      await tester.pumpAndSettle();
      expect(find.text('X-100'), findsOneWidget, reason: 'account open');

      // however long we wait, the account stays open and the sender closed
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('X-100'), findsOneWidget, reason: 'account still open');
      expect(find.text(senderMarker), findsNothing,
          reason: 'sender still closed');
      expect(save(tester).onPressed, isNull);

      // by hand: open the sender
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      expect(find.text(senderMarker), findsOneWidget, reason: 'sender opened');
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('شركة المرسل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Client>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أحمد').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final n = tester.widgetList(fields).length;
      await tester.enterText(fields.at(n - 2), 'R-1');
      await tester.enterText(fields.at(n - 1), '250');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // everything is filled, the reference too: it is still open
      expect(find.text(senderMarker), findsOneWidget,
          reason: 'the sender does not close by itself');
      expect(save(tester).onPressed, isNotNull, reason: 'ready to press');

      // and it closes only when tapped
      await tester.tap(find.text('الجهة المرسلة'));
      await tester.pumpAndSettle();
      expect(find.text(senderMarker), findsNothing, reason: 'closed by hand');
    });
  });
}
