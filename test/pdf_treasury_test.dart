import 'dart:typed_data';

import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/treasury/domain/lyd_treasury.dart';
import 'package:eshary/features/treasury/domain/profit_report.dart';
import 'package:eshary/features/treasury/domain/treasury_position.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 28, 8);

int _pages(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;

Transfer _out(int i, {bool rated = true}) => Transfer(
      id: 't$i',
      ownerId: 'o',
      companyId: 'c1',
      exchangeId: 'e1',
      beneficiaryName: 'مستفيد $i',
      beneficiaryAccountCompany: 'شركة',
      beneficiaryCode: 'B-$i',
      amount: 100.0 + i,
      reference: 'Rh${1000 + i}',
      status: TransferStatus.archived,
      createdAt: _t0.add(Duration(minutes: i)),
      archivedAt: _t0.add(Duration(minutes: i)),
      createdByEmployeeId: null,
      cancelledAt: i % 9 == 0 ? _t0.add(Duration(minutes: i + 1)) : null,
      rate: rated ? 7.35 : null,
      lydAmount: rated ? ((100.0 + i) * 735).round() / 100 : null,
      lydMethod: rated ? (i.isEven ? 'cash' : 'bank') : null,
    );

CurrencyBuy _buy(int i) => CurrencyBuy(
      id: 'b$i',
      ownerId: 'o',
      myCompanyId: 'c1',
      exchangeId: 'e1',
      clientId: null,
      clientFromAccount: 'عميل',
      usdAmount: 50.0 + i,
      rate: i.isEven ? 7.1 : null,
      lydAmount: i.isEven ? ((50.0 + i) * 710).round() / 100 : null,
      reference: '',
      status: CurrencyBuyStatus.archived,
      createdAt: _t0.add(Duration(minutes: i)),
      archivedAt: _t0.add(Duration(minutes: i)),
      createdByEmployeeId: null,
    );

ProfitRow _profit(int i) => ProfitRow(
      exchangeId: 'e$i',
      companyName: 'الرحالة الأولى',
      accountName: 'حساب $i',
      soldUsd: 1000.0 + i,
      salesLyd: (1000.0 + i) * 7.35,
      costLyd: (1000.0 + i) * 7.2,
      profitLyd: ((1000.0 + i) * 0.15 * 100).round() / 100,
      exitsPriced: 3,
      exitsUnpriced: i == 0 ? 1 : 0,
      unpricedUsd: i == 0 ? 100 : 0,
      boughtUsd: 500,
      boughtLyd: 3550,
      entriesPriced: 1,
    );

TreasuryPosition _position(int i) => TreasuryPosition(
      exchangeId: 'e$i',
      companyName: 'الرحالة الأولى',
      accountName: 'حساب $i',
      balance: 1000.0 * (i + 1),
      costRate: i == 2 ? null : 7.2,
      bookValue: i == 2 ? null : 7200.0 * (i + 1),
      costUpdatedAt: _t0,
      marketRate: 7.35,
      unrealized: i == 2 ? null : 150.0 * (i + 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final company = Company(
    id: 'c1',
    ownerId: 'o',
    name: 'الرحالة الأولى',
    startRef: 'Rh0100',
    createdAt: _t0,
  );
  final exchange = Exchange(
    id: 'e1',
    companyId: 'c1',
    name: 'بهاروز',
    balance: 1000,
    ourCode: 'X-1',
    country: null,
    createdAt: _t0,
  );

  for (final n in [0, 3, 120]) {
    test('the reports with the dinar, $n rows: built, paged', () async {
      final pdf = await PdfExport.load();
      final transfers = [for (var i = 0; i < n; i++) _out(i)];
      final buys = [for (var i = 0; i < n; i++) _buy(i)];
      final reports = <String, Uint8List>{
        'daily exits': await pdf.buildDailyTransfersReport(
          rows: transfers,
          companyNameById: {'c1': company.name},
          exchangeNameById: {'e1': exchange.name},
          exportedBy: 'المدير',
        ),
        'daily entries': await pdf.buildDailyBuysReport(
          rows: buys,
          companyNameById: {'c1': company.name},
          exchangeById: {'e1': exchange},
          clientById: const {},
          exportedBy: 'المدير',
        ),
        'outgoing details': await pdf.buildOutgoingDetailsReport(
          transfers: transfers,
          companyById: {'c1': company},
          exchangeById: {'e1': exchange},
          start: _t0,
          end: _t0.add(const Duration(hours: 12)),
          exportedBy: 'المدير',
        ),
        'income details': await pdf.buildIncomeDetailsReport(
          buys: buys,
          companyById: {'c1': company},
          exchangeById: {'e1': exchange},
          clientById: const {},
          start: _t0,
          end: _t0.add(const Duration(hours: 12)),
          exportedBy: 'المدير',
        ),
        'profit': await pdf.buildProfitReport(
          rows: [for (var i = 0; i < n; i++) _profit(i)],
          start: _t0,
          end: _t0.add(const Duration(hours: 12)),
          exportedBy: 'المدير',
        ),
        'treasury': await pdf.buildTreasuryReport(
          positions: [for (var i = 0; i < n; i++) _position(i)],
          dinars: LydSummary.fromJson(const {
            'open': true,
            'cash': 8800,
            'bank': 34100,
            'flows': <String, dynamic>{},
          }),
          exportedBy: 'المدير',
        ),
      };
      for (final e in reports.entries) {
        expect(e.value.length, greaterThan(1000), reason: e.key);
        expect(_pages(e.value), greaterThanOrEqualTo(1), reason: e.key);
        if (n == 120) {
          expect(_pages(e.value), greaterThan(1), reason: '${e.key} pages');
        }
      }
    });
  }

  test('older operations without a rate still print', () async {
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildDailyTransfersReport(
      rows: [for (var i = 0; i < 5; i++) _out(i, rated: false)],
      companyNameById: {'c1': company.name},
      exchangeNameById: {'e1': exchange.name},
      exportedBy: 'المدير',
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('a treasury report before the dinar treasury exists', () async {
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildTreasuryReport(
      positions: [_position(0)],
      exportedBy: 'المدير',
    );
    expect(bytes.length, greaterThan(1000));
  });
}

