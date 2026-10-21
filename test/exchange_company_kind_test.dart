import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ExchangeCompany _ec(String name, String kind) => ExchangeCompany(
      id: name,
      ownerId: 'u',
      name: name,
      country: 'تركيا',
      createdAt: DateTime(2026, 1, 1),
      kind: kind,
    );

final _all = [
  _ec('بهاروز', kExchangeCompanyMine),
  _ec('أنزار', kExchangeCompanyMine),
  _ec('الصحراء', kExchangeCompanyClient),
];

void main() {
  group('the two kinds', () {
    test('a company is mine unless the database says it is a customer\'s', () {
      Map<String, dynamic> row(Object? kind) => {
            'id': '1',
            'owner_id': 'u',
            'name': 'x',
            'created_at': '2026-10-01T00:00:00Z',
            if (kind != null) 'kind': kind,
          };
      expect(ExchangeCompany.fromJson(row(null)).isMine, isTrue,
          reason: 'a database without 0074');
      expect(ExchangeCompany.fromJson(row('mine')).isMine, isTrue);
      final c = ExchangeCompany.fromJson(row('client'));
      expect(c.isClient, isTrue);
      expect(c.isMine, isFalse);
    });

    test('two lists come out of the one table, and never overlap', () {
      final container = ProviderContainer(overrides: [
        exchangeCompaniesListProvider.overrideWith((ref) async => _all),
      ]);
      addTearDown(container.dispose);
      return container.read(exchangeCompaniesListProvider.future).then((_) {
        final mine = container.read(myExchangeCompaniesProvider).value!;
        final clients = container.read(clientCompaniesProvider).value!;
        expect(mine.map((c) => c.name), ['بهاروز', 'أنزار']);
        expect(clients.map((c) => c.name), ['الصحراء']);
        expect(mine.any(clients.contains), isFalse);
      });
    });
  });

  group('the settings screen', () {
    Future<void> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exchangeCompaniesListProvider.overrideWith((ref) async => _all),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: ExchangeCompaniesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('my companies and my customers\' companies are two lists',
        (tester) async {
      await open(tester);
      expect(find.text('شركات الصرافة الخاصة بي'), findsOneWidget);
      expect(find.text('شركات العملاء'), findsOneWidget);
      // each company sits under its own heading
      final mineTop =
          tester.getTopLeft(find.byKey(const ValueKey('kind-mine'))).dy;
      final clientTop =
          tester.getTopLeft(find.byKey(const ValueKey('kind-client'))).dy;
      expect(mineTop, lessThan(clientTop));
      for (final n in ['بهاروز', 'أنزار']) {
        expect(tester.getTopLeft(find.text(n)).dy, lessThan(clientTop),
            reason: '$n is mine');
      }
      expect(tester.getTopLeft(find.text('الصحراء')).dy, greaterThan(clientTop),
          reason: 'الصحراء is a customer\'s');
    });

    testWidgets(
        'each list has its own "+", and a customer company is added as one',
        (tester) async {
      await open(tester);
      expect(find.byTooltip('إضافة شركة صرافة لي'), findsOneWidget);
      expect(find.byTooltip('إضافة شركة عميل'), findsOneWidget);
      await tester.tap(find.byTooltip('إضافة شركة عميل'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة شركة عميل'), findsWidgets);
    });
  });

  testWidgets('editing a company can move it to the other list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exchangeCompaniesListProvider.overrideWith((ref) async => _all)
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body:
                  AddExchangeCompanyDialog(onSaved: () {}, existing: _all.last),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-kind')), findsOneWidget);
    expect(find.text('تعديل شركة عميل'), findsOneWidget);
  });

  group('where each list is used', () {
    String src(String f) => File(f).readAsStringSync();

    test('the exit / entry forms and حساباتي offer only MY companies', () {
      for (final f in [
        'lib/features/currency_buy/presentation/currency_buy_screen.dart',
        'lib/features/transfers/presentation/transfers_screen.dart',
        'lib/features/companies/presentation/accounts_screen.dart',
        'lib/features/companies/presentation/add_company_dialog.dart',
      ]) {
        final s = src(f);
        expect(s, contains('myExchangeCompaniesProvider'), reason: f);
        expect(s.contains('ref.watch(exchangeCompaniesListProvider)'), isFalse,
            reason: '$f must not read the mixed list');
      }
    });

    test(
        'the customer dialog offers customers\' companies, and adds them as such',
        () {
      final s = src('lib/features/clients/presentation/add_client_dialog.dart');
      expect(s, contains('clientCompaniesProvider'));
      expect(s, contains('kind: kExchangeCompanyClient'));
      expect(s.contains('ref.watch(exchangeCompaniesListProvider)'), isFalse);
    });

    test('0074 sorts the old names and adds the column', () {
      final sql = src('supabase/migrations/0074_exchange_company_kind.sql');
      expect(sql, contains("check (kind in ('mine', 'client'))"));
      expect(sql, contains("set kind = 'client'"));
    });
  });
}
