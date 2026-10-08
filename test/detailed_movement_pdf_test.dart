import 'dart:io';
import 'dart:typed_data';

import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// "تفاصيل حركة الدخول والخروج للحوالات" is an accountant-style statement:
/// دخول | خروج | الرصيد, where the balance rises with entries and falls with
/// exits. Entries are green, exits red. The "إشاري/كود" column holds the
/// account code for an entry and the reference for an exit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('running balance (دخول / خروج / الرصيد)', () {
    test('the accountant example: دخول 1000, خروج 350 → الرصيد 650', () {
      final l = ledgerOf([
        (isIncome: true, amount: 1000),
        (isIncome: false, amount: 350),
      ]);
      expect(l[0].income, 1000);
      expect(l[0].outgoing, isNull);
      expect(l[0].balance, 1000);
      expect(l[1].income, isNull);
      expect(l[1].outgoing, 350);
      expect(l[1].balance, 650);
    });

    test('the balance rises with entries and falls with exits, in order', () {
      final l = ledgerOf([
        (isIncome: true, amount: 500),
        (isIncome: false, amount: 200),
        (isIncome: true, amount: 100),
        (isIncome: false, amount: 50),
      ]);
      expect(l.map((e) => e.balance), [500, 300, 400, 350]);
    });

    test('exits first: the balance goes negative', () {
      final l = ledgerOf([
        (isIncome: false, amount: 120),
        (isIncome: true, amount: 100),
      ]);
      expect(l.map((e) => e.balance), [-120, -20]);
    });

    test('each line fills exactly one of دخول / خروج', () {
      final l = ledgerOf([
        (isIncome: true, amount: 10),
        (isIncome: false, amount: 4),
      ]);
      for (final e in l) {
        expect((e.income == null) != (e.outgoing == null), isTrue);
      }
    });

    test('no operations → no lines', () {
      expect(ledgerOf(const []), isEmpty);
    });
  });

  group('the table', () {
    final src = File('lib/shared/pdf_export.dart').readAsStringSync();
    final from = src.indexOf('buildDetailedTransfersReport');
    final body = src.substring(from);

    final headers = RegExp(r"const headers = <String>\[([\s\S]*?)\];")
        .firstMatch(body)!
        .group(1)!;
    final titles = RegExp(r"'([^']+)'")
        .allMatches(headers)
        .map((m) => m.group(1)!)
        .toList();

    test('columns, in order', () {
      expect(titles, [
        'ت',
        'الوقت',
        'التاريخ',
        'إشاري/كود',
        'حساباتي',
        'الجهة',
        'إشاري المرسل',
        'دخول',
        'خروج',
        'الرصيد',
      ]);
    });

    test('the old columns are gone', () {
      for (final gone in [
        'الرصيد قبل',
        'الرصيد بعد',
        'فرق تراكمي',
        'النوع',
        'قيمة العملية',
        'الإشاري',
      ]) {
        expect(titles, isNot(contains(gone)), reason: gone);
      }
    });

    test('there is one width for every column', () {
      final widths = RegExp(
        r"columnWidths: const \{([\s\S]*?)\},\s*children: tableChildren",
      ).firstMatch(body.substring(body.indexOf('Reversed indices: 0 = leftmost (الرصيد)')))!.group(1)!;
      expect(RegExp('FlexColumnWidth').allMatches(widths).length, titles.length);
    });

    test('the summaries read إجمالي الدخول | إجمالي الخروج | الرصيد', () {
      expect(body, contains("'إجمالي الدخول'"));
      expect(body, contains("'إجمالي الخروج'"));
      expect(body, isNot(contains("'فرق الحركة'")));
      expect(body, isNot(contains("'الرصيد قبل'")));
      expect(body, isNot(contains("'الرصيد بعد'")));
    });
  });

  group('the report builds', () {
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
    final buy = CurrencyBuy(
      id: 'b1',
      ownerId: 'o',
      myCompanyId: 'c1',
      exchangeId: 'e1',
      clientId: 'k1',
      clientFromAccount: 'حساب',
      usdAmount: 1000,
      rate: 5,
      lydAmount: 5000,
      reference: 'REF-IN-1',
      status: CurrencyBuyStatus.archived,
      createdAt: t0,
      archivedAt: t0,
      createdByEmployeeId: null,
    );
    final transfer = Transfer(
      id: 't1',
      ownerId: 'o',
      companyId: 'c1',
      exchangeId: 'e1',
      beneficiaryName: 'مستفيد',
      beneficiaryAccountCompany: 'شركة المستفيد',
      beneficiaryCode: 'B-9',
      amount: 350,
      reference: 'REF-OUT-1',
      status: TransferStatus.archived,
      createdAt: t0.add(const Duration(minutes: 5)),
      archivedAt: t0.add(const Duration(minutes: 5)),
      createdByEmployeeId: null,
    );

    test('with an entry and an exit', () async {
      final pdf = await PdfExport.load();
      final Uint8List bytes = await pdf.buildDetailedTransfersReport(
        buys: [buy],
        transfers: [transfer],
        companyById: {'c1': company},
        exchangeById: {'e1': exchange},
        clientById: {'k1': client},
        start: DateTime(2026, 10, 8),
        end: DateTime(2026, 10, 8, 23, 59),
      );
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
