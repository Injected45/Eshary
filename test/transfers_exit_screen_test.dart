import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/data/companies_repository.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/employee_auth/data/employee_auth_repository.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:eshary/features/transfers/presentation/transfers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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

var _liveExchanges = <Exchange>[];

Future<void> _open(
  WidgetTester tester,
  List<Exchange> exchanges, {
  double width = 400,
  EmployeeIdentity? identity,
  List<Transfer> today = const <Transfer>[],
}) async {
  await _loadFonts();
  _liveExchanges = exchanges;
  await tester.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allExchangesProvider.overrideWith((ref) async => _liveExchanges),
        companiesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _company(e.companyId)],
        ),
        exchangeCompaniesListProvider.overrideWith(
          (ref) async => [for (final e in exchanges) _ec(e.name)],
        ),
        currentEmployeeProvider.overrideWith((ref) async => identity),
        todayTransfersProvider.overrideWith((ref) async => today),
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

    expect(dy('رصيد الحساب'), dy('كود الحساب'));
    expect(dy('الرقم الإشاري'), dy('القيمة بالدولار (USD)'));
    expect(dy('الرقم الإشاري'), greaterThan(dy('رصيد الحساب')));
    // Right-to-left: the first field sits on the right.
    expect(dx('رصيد الحساب'), greaterThan(dx('كود الحساب')));
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
    expect(find.text('يتجاوز رصيد الحساب'), findsOneWidget);
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
      expect(find.textContaining('يتجاوز رصيد الحساب'), findsWidgets);
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

  group('the four boxes of "خروج من حسابي" are identical in size', () {
    /// Sizes of: balance box, account code, reference, amount.
    List<Size> boxes(WidgetTester tester) {
      final fields = find.byType(TextField); // code, reference, amount
      expect(fields, findsNWidgets(3));
      final balance = find
          .ancestor(of: find.text('2,500.00'), matching: find.byType(SizedBox))
          .first;
      return [
        tester.getSize(balance),
        for (var i = 0; i < 3; i++) tester.getSize(fields.at(i)),
      ];
    }

    void expectEqual(List<Size> sizes) {
      for (final s in sizes) {
        expect(s.height, sizes.first.height, reason: '$sizes');
        expect((s.width - sizes.first.width).abs(), lessThan(0.5),
            reason: '$sizes');
      }
    }

    final one = [_exchange('1', 'شركة الصرافة', 'X-100', 2500)];

    testWidgets('no icons inside the four boxes (the label says it all)',
        (tester) async {
      await _open(tester, one);
      final fields = find.byType(TextField);
      for (var i = 0; i < 3; i++) {
        expect(
          find.descendant(of: fields.at(i), matching: find.byType(FaIcon)),
          findsNothing,
          reason: 'text field #$i',
        );
      }
      final balance = find
          .ancestor(of: find.text('2,500.00'), matching: find.byType(SizedBox))
          .first;
      expect(
        find.descendant(of: balance, matching: find.byType(FaIcon)),
        findsNothing,
        reason: 'balance box',
      );
    });

    testWidgets('the text sits in the middle of each box', (tester) async {
      await _open(tester, one);
      final box = tester.getCenter(find
          .ancestor(of: find.text('2,500.00'), matching: find.byType(SizedBox))
          .first);
      final text = tester.getCenter(find.text('2,500.00'));
      expect((text.dx - box.dx).abs(), lessThan(1), reason: 'balance');
      await tester.enterText(find.byType(TextField).at(2), '100');
      await tester.pumpAndSettle();
      final amountBox = tester.getCenter(find.byType(TextField).at(2));
      final amountText = tester.getCenter(find.text('100'));
      expect((amountText.dx - amountBox.dx).abs(), lessThan(2),
          reason: 'amount');
    });

    testWidgets('normal state', (tester) async {
      await _open(tester, one);
      expectEqual(boxes(tester));
    });

    testWidgets('with a typed amount, even a huge one', (tester) async {
      await _open(tester, one);
      await tester.enterText(find.widgetWithText(TextField, ''), '123456789');
      await tester.pumpAndSettle();
      expectEqual(boxes(tester));
    });

    testWidgets('amount over the limit keeps the same height', (tester) async {
      await _open(tester, one);
      await tester.enterText(find.widgetWithText(TextField, ''), '99999');
      await tester.pumpAndSettle();
      expect(find.text('يتجاوز رصيد الحساب'), findsOneWidget);
      expectEqual(boxes(tester));
    });

    testWidgets('on a narrow 320 phone', (tester) async {
      await _open(tester, one, width: 320);
      expectEqual(boxes(tester));
    });
  });

  group('exits are posted at save: no daily close', () {
    final one = [_exchange('1', 'شركة الصرافة', 'X-100', 2500)];

    Transfer row(String id, double amount) => Transfer(
          id: id,
          ownerId: 'o',
          companyId: 'c1',
          exchangeId: '1',
          beneficiaryName: 'مستفيد',
          beneficiaryAccountCompany: null,
          beneficiaryCode: null,
          amount: amount,
          reference: 'R-$id',
          status: TransferStatus.archived,
          createdAt: DateTime.now(),
          archivedAt: DateTime.now(),
          createdByEmployeeId: null,
        );

    testWidgets('there is no daily-close button, for the admin', (tester) async {
      await _open(tester, one);
      expect(find.textContaining('الإقفال اليومي'), findsNothing);
      expect(find.textContaining('ترحيل'), findsNothing);
    });

    testWidgets('…nor for an employee, whatever was stored for them',
        (tester) async {
      await _open(
        tester,
        one,
        identity: const EmployeeIdentity(
          sessionId: 's',
          subUserId: 'u',
          parentAdminId: 'a',
          employeeName: 'رافع',
          // old stored keys must not bring the button back
          permissions: ['transfers_create', 'archive_transfers'],
          branchId: null,
        ),
      );
      expect(find.textContaining('الإقفال اليومي'), findsNothing);
    });

    testWidgets("the day's list shows today's executed exits", (tester) async {
      await _open(tester, one, today: [row('1', 100), row('2', 250)]);
      expect(find.text('خروج منفذ'), findsOneWidget);
      expect(find.text('(2)'), findsOneWidget, reason: 'count badge');
    });

    testWidgets('with nothing today the list is empty (a new day starts clean)',
        (tester) async {
      await _open(tester, one);
      expect(find.text('(0)'), findsOneWidget, reason: 'count badge');
    });

    testWidgets('the balance shown follows the account after a save',
        (tester) async {
      await _open(tester, one);
      expect(find.text('2,500.00'), findsOneWidget);
      // a save moved the balance on the server; the list is refreshed
      _liveExchanges = [_exchange('1', 'شركة الصرافة', 'X-100', 2200)];
      ProviderScope.containerOf(tester.element(find.byType(TransfersScreen)))
          .invalidate(allExchangesProvider);
      await tester.pumpAndSettle();
      expect(find.text('2,200.00'), findsOneWidget);
      expect(find.text('2,500.00'), findsNothing);
      // …and an exit above the NEW balance is refused
      await tester.enterText(find.widgetWithText(TextField, ''), '2300');
      await tester.pumpAndSettle();
      expect(find.text('يتجاوز رصيد الحساب'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(2), '2200');
      await tester.pumpAndSettle();
      expect(find.text('يتجاوز رصيد الحساب'), findsNothing);
    });
  });
}
