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

  group('the delete button', () {
    Future<void> open(
      WidgetTester tester,
      Map<String, ExchangeCompanyUsage>? usage,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exchangeCompaniesListProvider.overrideWith((ref) async => _all),
            exchangeCompanyUsageProvider.overrideWith((ref) async {
              if (usage == null) throw Exception('not loaded');
              return usage;
            }),
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

    Finder del(String id) => find.byKey(ValueKey('company-delete-$id'));

    testWidgets('only a name that was never used keeps its delete button',
        (tester) async {
      await open(tester, {
        // an account and operations
        'بهاروز':
            const ExchangeCompanyUsage(accounts: 1, parties: 0, operations: 4),
        // an account, no operation yet
        'أنزار':
            const ExchangeCompanyUsage(accounts: 1, parties: 0, operations: 0),
        // registered and never used
        'الصحراء':
            const ExchangeCompanyUsage(accounts: 0, parties: 0, operations: 0),
      });
      expect(del('بهاروز'), findsNothing,
          reason: 'operations: no button at all');
      expect(del('أنزار'), findsNothing,
          reason: 'it has an account: no button');
      expect(del('الصحراء'), findsOneWidget, reason: 'a name only');
      // the edit pencil stays on every one
      expect(find.byTooltip('تعديل'), findsNWidgets(3));
    });

    testWidgets('a company with a saved party or operations only has no button',
        (tester) async {
      await open(tester, {
        'بهاروز':
            const ExchangeCompanyUsage(accounts: 0, parties: 2, operations: 0),
        'أنزار':
            const ExchangeCompanyUsage(accounts: 0, parties: 0, operations: 1),
        'الصحراء':
            const ExchangeCompanyUsage(accounts: 0, parties: 0, operations: 0),
      });
      expect(del('بهاروز'), findsNothing);
      expect(del('أنزار'), findsNothing);
      expect(del('الصحراء'), findsOneWidget);
    });

    testWidgets('while the usage is unknown, no delete button is offered',
        (tester) async {
      await open(tester, null);
      for (final n in ['بهاروز', 'أنزار', 'الصحراء']) {
        expect(del(n), findsNothing, reason: n);
      }
    });
  });

  test('the usage comes from the database', () {
    final repo = File(
            'lib/features/exchange_companies/data/exchange_companies_repository.dart')
        .readAsStringSync();
    expect(repo, contains("'exchange_company_usage'"));
    final sql =
        File('supabase/migrations/0076_company_usage.sql').readAsStringSync();
    expect(sql, contains('function exchange_company_usage'));
    expect(sql, contains('company_in_use_operations'));
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
