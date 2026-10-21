import 'dart:io';
import 'dart:typed_data';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/clients/presentation/clients_providers.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buys_providers.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/reports/domain/party_report.dart';
import 'package:eshary/features/reports/presentation/party_report_screen.dart';
import 'package:eshary/features/reports/presentation/reports_screen.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.now();

CurrencyBuy _buy(String id, String? clientId, double usd, {String? from}) =>
    CurrencyBuy(
      id: id,
      ownerId: 'o',
      myCompanyId: 'c1',
      exchangeId: 'e1',
      clientId: clientId,
      clientFromAccount: from,
      usdAmount: usd,
      rate: 5,
      lydAmount: usd * 5,
      reference: 'R$id',
      status: CurrencyBuyStatus.archived,
      createdAt: _t0,
      archivedAt: _t0,
      createdByEmployeeId: null,
    );

Transfer _transfer(
  String id,
  double amount, {
  String name = '',
  String? company,
  String? code,
}) =>
    Transfer(
      id: id,
      ownerId: 'o',
      companyId: 'c1',
      exchangeId: 'e1',
      beneficiaryName: name,
      beneficiaryAccountCompany: company,
      beneficiaryCode: code,
      amount: amount,
      reference: 'T$id',
      status: TransferStatus.archived,
      createdAt: _t0,
      archivedAt: _t0,
      createdByEmployeeId: null,
    );

Client _client(String id, String name, {String? company, String? code}) =>
    Client(
      id: id,
      ownerId: 'o',
      name: name,
      company: company,
      code: code,
      createdAt: _t0,
    );

void main() {
  final clients = {
    'k1': _client('k1', 'أحمد', company: 'شركة الصحراء', code: '5521'),
    'k2': _client('k2', 'سالم', company: 'شركة النور', code: '77'),
  };
  final buys = [
    _buy('b1', 'k1', 1000),
    _buy('b2', 'k2', 400),
    _buy('b3', null, 50, from: 'حساب حر'),
  ];
  final transfers = [
    _transfer('t1', 300, name: 'خالد', company: 'شركة الصحراء', code: '9001'),
    _transfer('t2', 120, name: 'منى', company: 'شركة النور', code: '٥٥٢١'),
    _transfer('t3', 10, name: 'بلا شركة'),
  ];

  group('which operations belong to a party', () {
    test('by company: entries and exits of the same company', () {
      final r = operationsOfParty(
        field: PartyField.company,
        query: 'شركة الصحراء',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(r.buys.map((b) => b.id), ['b1']);
      expect(r.transfers.map((t) => t.id), ['t1']);
    });

    test('a company matches by what it contains, without case', () {
      final r = operationsOfParty(
        field: PartyField.company,
        query: 'النور',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(r.buys.map((b) => b.id), ['b2']);
      expect(r.transfers.map((t) => t.id), ['t2']);
    });

    test('by name: a saved sender, a typed account and a beneficiary', () {
      final saved = operationsOfParty(
        field: PartyField.name,
        query: 'أحمد',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(saved.buys.map((b) => b.id), ['b1']);
      final typed = operationsOfParty(
        field: PartyField.name,
        query: 'حساب حر',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(typed.buys.map((b) => b.id), ['b3']);
      final beneficiary = operationsOfParty(
        field: PartyField.name,
        query: 'خالد',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(beneficiary.transfers.map((t) => t.id), ['t1']);
    });

    test('by code: the same code whatever the digit shape; never a part', () {
      final r = operationsOfParty(
        field: PartyField.code,
        query: '5521',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(r.buys.map((b) => b.id), ['b1']);
      expect(r.transfers.map((t) => t.id), ['t2']); // ٥٥٢١ = 5521
      final part = operationsOfParty(
        field: PartyField.code,
        query: '55',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(part.buys, isEmpty);
      expect(part.transfers, isEmpty);
    });

    test('nothing typed finds nothing', () {
      final r = operationsOfParty(
        field: PartyField.company,
        query: '  ',
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(r.buys, isEmpty);
      expect(r.transfers, isEmpty);
    });

    test('the values to pick from are distinct and not empty', () {
      final companies = partyValues(
        PartyField.company,
        buys: buys,
        transfers: transfers,
        clientById: clients,
      );
      expect(companies, ['شركة النور', 'شركة الصحراء']..sort());
    });
  });

  group('the PDF', () {
    test('is the movement statement with the party in its header', () async {
      final pdf = await PdfExport.load();
      final Uint8List bytes = await pdf.buildDetailedTransfersReport(
        buys: [buys[0]],
        transfers: [transfers[0]],
        companyById: {
          'c1': Company(
            id: 'c1',
            ownerId: 'o',
            name: 'شركة الرحالة',
            startRef: 'A1',
            createdAt: _t0,
          ),
        },
        exchangeById: {
          'e1': Exchange(
            id: 'e1',
            companyId: 'c1',
            name: 'شركة الصرافة',
            balance: 1000,
            ourCode: 'X-100',
            country: null,
            createdAt: _t0,
          ),
        },
        clientById: clients,
        start: DateTime(_t0.year, _t0.month, _t0.day),
        end: DateTime(_t0.year, _t0.month, _t0.day, 23, 59),
        title: 'تقرير المعاملات مع الشركة: شركة الصحراء',
        scopeLabel: 'الجهة: الشركة — شركة الصحراء',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });

    test('the report reuses the movement builder, not a copy of it', () {
      final screen = File(
        'lib/features/reports/presentation/party_report_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('buildDetailedTransfersReport('));
      expect(screen, contains('scopeLabel: scopeLabel'));
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentEmployeeProvider.overrideWith((ref) async => null),
            archivedBuysProvider.overrideWith((ref) async => buys),
            archivedTransfersProvider.overrideWith((ref) async => transfers),
            clientsListProvider
                .overrideWith((ref) async => clients.values.toList()),
          ],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [],
            ),
            home: const PartyReportScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks for a party before showing anything', (tester) async {
      await pump(tester);
      expect(find.textContaining('اختر الشركة'), findsOneWidget);
      expect(find.byKey(const ValueKey('party-report-net')), findsNothing);
    });

    testWidgets('typing a company shows its totals', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'الصحراء');
      await tester.pumpAndSettle();
      // entry 1000, exit 300 → net +700
      expect(find.byKey(const ValueKey('party-report-net')), findsOneWidget);
      expect(find.text('+\$700.00'), findsOneWidget);
    });

    testWidgets('a code that nobody used says so', (tester) async {
      await pump(tester);
      await tester.tap(find.text('الكود'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '000');
      await tester.pumpAndSettle();
      expect(find.textContaining('لا توجد معاملات'), findsOneWidget);
    });
  });

  testWidgets('the list of reports opens the party report', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentEmployeeProvider.overrideWith((ref) async => null),
          archivedBuysProvider.overrideWith((ref) async => buys),
          archivedTransfersProvider.overrideWith((ref) async => transfers),
          clientsListProvider
              .overrideWith((ref) async => clients.values.toList()),
          companiesListProvider.overrideWith((ref) async => const <Company>[]),
          allExchangesProvider.overrideWith((ref) async => const <Exchange>[]),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Scaffold(body: ReportsScreen()),
        ),
      ),
    );
    expect(find.text('تقرير حسب الجهة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-party')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('party-report-field')), findsOneWidget);
  });

  test('the tab is for the admin only', () {
    final shell = File('lib/features/home/presentation/home_shell.dart')
        .readAsStringSync();
    expect(shell, contains('!ref.watch(isEmployeeProvider)'));
    expect(shell, contains("label: 'التقارير'"));
    expect(AppColors.accent, isNotNull);
  });
}
