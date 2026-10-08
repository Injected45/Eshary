import 'dart:io';
import 'dart:typed_data';

import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every printed report builds (empty, one row, and enough rows to need
/// several pages), each with the export line as its last line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 8, 12);
  final company = Company(
    id: 'c1',
    ownerId: 'o',
    name: 'شركة الرحالة',
    startRef: 'A1',
    createdAt: t0,
  );
  final exchange = Exchange(
    id: 'e1',
    companyId: 'c1',
    name: 'شركة الصرافة',
    balance: 1000,
    ourCode: 'X-100',
    country: null,
    createdAt: t0,
  );
  final client = Client(
    id: 'k1',
    ownerId: 'o',
    name: 'عميل',
    company: 'شركة العميل',
    code: 'K-7',
    createdAt: t0,
  );

  CurrencyBuy buy(int i) => CurrencyBuy(
        id: 'b$i',
        ownerId: 'o',
        myCompanyId: 'c1',
        exchangeId: 'e1',
        clientId: 'k1',
        clientFromAccount: 'حساب',
        usdAmount: 100.0 + i,
        rate: 5,
        lydAmount: 500,
        reference: 'IN-$i',
        status: CurrencyBuyStatus.archived,
        createdAt: t0.add(Duration(minutes: i)),
        archivedAt: t0.add(Duration(minutes: i)),
        createdByEmployeeId: null,
      );
  Transfer transfer(int i) => Transfer(
        id: 't$i',
        ownerId: 'o',
        companyId: 'c1',
        exchangeId: 'e1',
        beneficiaryName: 'مستفيد',
        beneficiaryAccountCompany: 'شركة المستفيد',
        beneficiaryCode: 'B-9',
        amount: 50.0 + i,
        reference: 'OUT-$i',
        status: TransferStatus.archived,
        createdAt: t0.add(Duration(minutes: i)),
        archivedAt: t0.add(Duration(minutes: i)),
        createdByEmployeeId: null,
      );

  int pages(Uint8List bytes) =>
      RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;

  /// The drawing instructions of every page (content streams hold text).
  List<String> pageStreams(Uint8List bytes) {
    final raw = String.fromCharCodes(bytes);
    final out = <String>[];
    var i = 0;
    final re = RegExp(r'stream\r?\n');
    while (true) {
      final m = re.firstMatch(raw.substring(i));
      if (m == null) break;
      final s = i + m.end;
      final e = raw.indexOf('endstream', s);
      try {
        final txt = String.fromCharCodes(ZLibCodec().decode(bytes.sublist(s, e)));
        if (txt.contains(' Tf')) out.add(txt);
      } catch (_) {}
      i = e + 9;
    }
    return out;
  }

  /// Absolute y (from the bottom edge) of every text run on a page.
  List<double> textYs(String stream) {
    final ys = <double>[];
    final stack = <double>[];
    var ty = 0.0;
    final nums = <double>[];
    for (final tok in stream.split(RegExp(r'\s+'))) {
      final n = double.tryParse(tok);
      if (n != null) {
        nums.add(n);
        continue;
      }
      switch (tok) {
        case 'q':
          stack.add(ty);
        case 'Q':
          if (stack.isNotEmpty) ty = stack.removeLast();
        case 'cm':
          if (nums.length >= 6) ty += nums[nums.length - 1];
        case 'Td':
          if (nums.length >= 2) ys.add(ty + nums[nums.length - 1]);
        default:
      }
      nums.clear();
    }
    return ys;
  }

  final start = DateTime(2026, 10, 8);
  final end = DateTime(2026, 10, 8, 23, 59);
  final companies = {'c1': company};
  final exchanges = {'e1': exchange};
  final clients = {'k1': client};

  /// Builds all six reports with [n] rows.
  Future<Map<String, Uint8List>> allReports(int n) async {
    final pdf = await PdfExport.load();
    final buys = [for (var i = 0; i < n; i++) buy(i)];
    final transfers = [for (var i = 0; i < n; i++) transfer(i)];
    return {
      'daily exits': await pdf.buildDailyTransfersReport(
        rows: transfers,
        companyNameById: {'c1': company.name},
        exchangeNameById: {'e1': exchange.name},
        exportedBy: 'المدير',
      ),
      'daily entries': await pdf.buildDailyBuysReport(
        rows: buys,
        companyNameById: {'c1': company.name},
        exchangeById: exchanges,
        clientById: clients,
        exportedBy: 'المدير',
      ),
      'detailed movement': await pdf.buildDetailedTransfersReport(
        buys: buys,
        transfers: transfers,
        companyById: companies,
        exchangeById: exchanges,
        clientById: clients,
        start: start,
        end: end,
        exportedBy: 'المدير',
      ),
      'income details': await pdf.buildIncomeDetailsReport(
        buys: buys,
        companyById: companies,
        exchangeById: exchanges,
        clientById: clients,
        start: start,
        end: end,
        exportedBy: 'المدير',
      ),
      'outgoing details': await pdf.buildOutgoingDetailsReport(
        transfers: transfers,
        companyById: companies,
        exchangeById: exchanges,
        start: start,
        end: end,
        exportedBy: 'المدير',
      ),
    };
  }

  // The export line (date, time, who) is the LAST line of every page. The
  // footer is painted on the page's bottom margin, so a page with a single row
  // has it at the very bottom just like a full page.
  group('the export line is at the bottom of EVERY page', () {
    // A horizontal rule `0 y m W y l S` drawn within 40pt of the bottom margin:
    // the top border of the export line.
    final footerRule = RegExp(r'\n?0 ([0-9.]+) m [0-9.]+ \1 l S');

    for (final n in [0, 1, 80]) {
      test('with $n rows', () async {
        for (final e in (await allReports(n)).entries) {
          final streams = pageStreams(e.value);
          expect(streams, isNotEmpty, reason: e.key);
          for (var p = 0; p < streams.length; p++) {
            final low = footerRule
                .allMatches(streams[p])
                .map((m) => double.parse(m.group(1)!))
                .where((y) => y < 40)
                .toList();
            expect(low, isNotEmpty,
                reason: '${e.key}: page ${p + 1} has no footer rule near the bottom');
          }
        }
      });
    }

    test('a nearly empty page: content at the top, export line at the bottom',
        () async {
      // Landscape A4 is 595pt tall.
      for (final e in (await allReports(1)).entries) {
        final ys = textYs(pageStreams(e.value).first)..sort();
        expect(ys, isNotEmpty, reason: e.key);
        expect(ys.last, greaterThan(450),
            reason: '${e.key}: content should start near the top edge');
        expect(ys.first, lessThan(45),
            reason: '${e.key}: the export line should be at the very bottom');
      }
    });
  });

  test('the single-record sheet (portrait A4): same top and bottom rules',
      () async {
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildTable(
      title: 'تفاصيل الحوالة',
      headers: const ['الحقل', 'القيمة'],
      rows: const [
        ['الرقم الإشاري', 'R-1'],
        ['القيمة بالدولار', '300 dollars'],
      ],
      exportedBy: 'المدير',
    );
    final ys = textYs(pageStreams(bytes).first)..sort();
    expect(ys, isNotEmpty);
    // Portrait A4 is 842pt tall.
    expect(ys.last, greaterThan(700), reason: 'starts at the top');
    expect(ys.first, lessThan(60), reason: 'export line at the bottom');
  });

  group('every report builds', () {
    for (final n in [0, 1, 80]) {
      test('with $n rows', () async {
        final pdf = await PdfExport.load();
        final buys = [for (var i = 0; i < n; i++) buy(i)];
        final transfers = [for (var i = 0; i < n; i++) transfer(i)];

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
            exchangeById: exchanges,
            clientById: clients,
            exportedBy: 'المدير',
          ),
          'detailed movement': await pdf.buildDetailedTransfersReport(
            buys: buys,
            transfers: transfers,
            companyById: companies,
            exchangeById: exchanges,
            clientById: clients,
            start: start,
            end: end,
            exportedBy: 'المدير',
          ),
          'income details': await pdf.buildIncomeDetailsReport(
            buys: buys,
            companyById: companies,
            exchangeById: exchanges,
            clientById: clients,
            start: start,
            end: end,
            exportedBy: 'المدير',
          ),
          'outgoing details': await pdf.buildOutgoingDetailsReport(
            transfers: transfers,
            companyById: companies,
            exchangeById: exchanges,
            start: start,
            end: end,
            exportedBy: 'المدير',
          ),
          'single record': await pdf.buildTable(
            title: 'تفاصيل',
            headers: const ['الحقل', 'القيمة'],
            rows: const [
              ['الرقم الإشاري', 'R-1'],
            ],
            exportedBy: 'المدير',
          ),
        };

        for (final e in reports.entries) {
          expect(String.fromCharCodes(e.value.take(5)), '%PDF-',
              reason: e.key);
          expect(pages(e.value), greaterThanOrEqualTo(1), reason: e.key);
          if (n == 80 && e.key != 'single record') {
            expect(pages(e.value), greaterThan(1),
                reason: '${e.key} should need several pages');
          }
        }
      });
    }
  });
}
