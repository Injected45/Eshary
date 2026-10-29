import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/data/companies_repository.dart';
import 'package:eshary/features/companies/data/exchanges_repository.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/add_company_dialog.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 9);

/// Every call the dialog makes, in order.
final _calls = <String>[];

class _Companies implements CompaniesRepository {
  @override
  Future<Company> create({
    required String ownerId,
    required String name,
    required String startRef,
  }) async {
    _calls.add('company $name');
    return Company(
      id: 'c1',
      ownerId: ownerId,
      name: name,
      startRef: startRef,
      createdAt: _t0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Exchanges implements ExchangesRepository {
  _Exchanges({this.failures = 0});

  /// How many first calls fail (the network, the licence).
  int failures;

  @override
  Future<Exchange> create({
    required String companyId,
    required String name,
    required double balance,
    String? ourCode,
    String? country,
    double? costRate,
  }) async {
    if (failures > 0) {
      failures--;
      throw Exception('license_inactive');
    }
    _calls.add('exchange $balance cost $costRate');
    return Exchange(
      id: 'e1',
      companyId: companyId,
      name: name,
      balance: balance,
      ourCode: ourCode,
      country: country,
      createdAt: _t0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _open(
  WidgetTester tester, {
  bool employee = false,
  int accountFailures = 0,
}) async {
  _calls.clear();
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companiesRepositoryProvider.overrideWithValue(_Companies()),
        exchangesRepositoryProvider
            .overrideWithValue(_Exchanges(failures: accountFailures)),
        currentUserIdProvider.overrideWithValue('o'),
        isEmployeeProvider.overrideWithValue(employee),
        exchangeCompaniesListProvider.overrideWith(
          (ref) async => [
            ExchangeCompany(
              id: 'x',
              ownerId: 'o',
              name: 'بهاروز',
              country: 'تركيا',
              createdAt: _t0,
              kind: kExchangeCompanyMine,
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AddCompanyDialog(onSaved: () => _calls.add('saved')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String balance = '100'}) async {
  final dropdowns = find.byType(DropdownButtonFormField<String>);
  await tester.tap(dropdowns.at(0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('تركيا').last);
  await tester.pumpAndSettle();
  await tester.tap(dropdowns.at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('بهاروز').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'إسم الحساب'),
    'الرحالة',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'الرصيد الإفتتاحي'),
    balance,
  );
  await tester.pump();
}

String? _total(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('opening-cost-total'))).data;

void main() {
  testWidgets('100\$ at 9.5 costs 950 dinars, saved with the account',
      (tester) async {
    await _open(tester);
    await _fill(tester);
    expect(_total(tester), '—');
    await tester.enterText(find.byKey(const ValueKey('opening-cost')), '9.5');
    await tester.pump();
    expect(_total(tester), '950.00 د.ل');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, [
      'company الرحالة',
      'exchange 100.0 cost 9.5',
      'saved',
    ]);
  });

  testWidgets('a comma is the decimal point of the cost', (tester) async {
    await _open(tester);
    await _fill(tester, balance: '1,250');
    await tester.enterText(find.byKey(const ValueKey('opening-cost')), '7,25');
    await tester.pump();
    expect(_total(tester), '9,062.50 د.ل');
  });

  testWidgets('dollars without a cost are refused before anything is saved',
      (tester) async {
    await _open(tester);
    await _fill(tester);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, isEmpty);
    expect(find.textContaining('اكتب تكلفة الإفتتاحي'), findsOneWidget);
  });

  testWidgets('a cost out of range is refused before anything is saved',
      (tester) async {
    await _open(tester);
    await _fill(tester);
    await tester.enterText(find.byKey(const ValueKey('opening-cost')), '950');
    await tester.pump();
    expect(_total(tester), '—');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, isEmpty);
    expect(find.textContaining('أكبر من 1 وحتى 100'), findsOneWidget);
  });

  testWidgets('an empty account needs no cost', (tester) async {
    await _open(tester);
    await _fill(tester, balance: '0');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, ['company الرحالة', 'exchange 0.0 cost null', 'saved']);
  });

  testWidgets(
      'the account refused: a second press does not add the company again',
      (tester) async {
    await _open(tester, accountFailures: 1);
    await _fill(tester);
    await tester.enterText(find.byKey(const ValueKey('opening-cost')), '9.5');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, ['company الرحالة'], reason: 'the account was refused');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, ['company الرحالة', 'exchange 100.0 cost 9.5', 'saved']);
  });

  testWidgets('an employee never sees the cost', (tester) async {
    await _open(tester, employee: true);
    expect(find.byKey(const ValueKey('opening-cost')), findsNothing);
    await _fill(tester);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(_calls, ['company الرحالة', 'exchange 100.0 cost null', 'saved']);
  });
}
