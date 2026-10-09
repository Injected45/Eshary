import 'dart:io';
import 'dart:typed_data';

import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/ledger.dart';
import 'package:eshary/shared/pdf_export.dart';
import 'package:eshary/shared/period_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// The period reports (تفاصيل حركة الدخول والخروج, حوالات الدخول, حوالات
/// الخروج) and the account statement share one look and one way of being built
/// (lib/shared/pdf_export_period.dart): centred columns, totals once under the
/// table, "إشاري/كود" where the column holds a code for an entry and a
/// reference for an exit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final src = File('lib/shared/pdf_export_period.dart').readAsStringSync();
  String between(String from, String to) {
    final a = src.indexOf(from);
    if (a < 0) throw StateError('not found: $from');
    final b = src.indexOf(to, a + from.length);
    return src.substring(a, b < 0 ? src.length : b);
  }

  List<String> titlesOf(String code) {
    final headers = RegExp(r'(?:const )?headers = <String>\[([\s\S]*?)\];')
        .firstMatch(code)!
        .group(1)!;
    return RegExp(r"'([^']+)'")
        .allMatches(headers)
        .map((m) => m.group(1)!)
        .toList();
  }

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

  group('تفاصيل حركة الدخول والخروج', () {
    final code = between('Future<Uint8List> buildDetailedTransfersReport', 'Future<Uint8List> buildAccountStatement');

    test('columns, in order', () {
      expect(titlesOf(code), [
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
        expect(titlesOf(code), isNot(contains(gone)), reason: gone);
      }
    });

    test('one width for every column', () {
      final widths = RegExp(r'const widths = <double>\[([^\]]*)\]')
          .firstMatch(code)!
          .group(1)!
          .split(',')
          .where((w) => w.trim().isNotEmpty);
      expect(widths.length, titlesOf(code).length);
    });

    test('the totals appear once, under the table', () {
      expect(RegExp("'إجمالي الدخول'").allMatches(code).length, 1);
      expect(RegExp("'إجمالي الخروج'").allMatches(code).length, 1);
      expect(code, isNot(contains("'فرق الحركة'")));
      expect(code.indexOf('_reportTable('), lessThan(code.indexOf('_statRow(')));
      expect(RegExp('_statRow\\(').allMatches(code).length, 1);
    });
  });

  group('حوالات الدخول إلى حساباتي / حوالات الخروج من حساباتي', () {
    // _buildKindReport is the last method of the extension
    final kind = src.substring(src.indexOf('Future<Uint8List> _buildKindReport'));

    test('كود الحساب comes before حساباتي, and إشاري after it', () {
      final t = titlesOf(kind);
      expect(t, [
        'ت',
        'الوقت',
        'التاريخ',
        'كود الحساب',
        'حساباتي',
        'إشاري',
        'الجهة',
        'القيمة',
      ]);
      expect(t.indexOf('كود الحساب'), lessThan(t.indexOf('إشاري')));
    });

    test('same mechanism as the movement report', () {
      for (final piece in [
        '_periodHeader(',
        '_identityStrip(',
        '_reportTable(',
        '_statRow(',
        '_addReportPages(',
      ]) {
        expect(kind, contains(piece), reason: piece);
      }
    });

    test('both reports go through it and take the employee name', () {
      final income = between('Future<Uint8List> buildIncomeDetailsReport', 'Future<Uint8List> buildOutgoingDetailsReport');
      final outgoing = between('Future<Uint8List> buildOutgoingDetailsReport', 'Future<Uint8List> _buildKindReport');
      for (final c in [income, outgoing]) {
        expect(c, contains('_buildKindReport('));
        expect(c, contains('String? employeeName'));
      }
    });
  });

  group('shared look', () {
    test('every column and its data are centred (no right-aligned cells)', () {
      expect(src, isNot(contains('rightAlign')));
      expect(src, contains('alignment: pw.Alignment.center'));
    });

    test('the period sits on the left edge of the page', () {
      final header = between('pw.Widget _periodHeader(', 'pw.Widget _periodHeaderTop(');
      // the period is aligned physically left, and is the only place it is drawn
      final at = header.indexOf("'الفترة: \$period'");
      expect(at, greaterThan(0));
      expect(header.lastIndexOf('pw.Alignment.centerLeft', at), greaterThan(0));
      expect(RegExp("'الفترة:").allMatches(src).length, 1);
    });

    test('every table line is black (grey lines fade when printed)', () {
      final files = {
        'lib/shared/pdf_export.dart': File('lib/shared/pdf_export.dart').readAsStringSync(),
        'lib/shared/pdf_export_period.dart': src,
      };
      var tables = 0;
      for (final e in files.entries) {
        // from "pw.Table(" to its column widths: the border definition
        for (final m in RegExp(r'pw\.Table\(\s*border:[\s\S]*?columnWidths').allMatches(e.value)) {
          tables++;
          expect(m.group(0), isNot(contains('grey')), reason: e.key);
          expect(m.group(0), contains('PdfColors.black'), reason: e.key);
        }
      }
      expect(tables, 3, reason: 'daily exits, daily entries, shared report table');
      // the single-record sheet writes its black lines down too
      expect(files['lib/shared/pdf_export.dart'],
          contains('border: pw.TableBorder.all(color: PdfColors.black)'));
    });

    test('table text is black unless it is an entry (green) or an exit (red)', () {
      final cell = between('pw.Widget _reportCell(', 'pw.Widget _reportTable(');
      expect(cell, contains('color ?? PdfColors.black'));
    });

    test('a cell is never clipped (a clipped cell lost its last letter)', () {
      final cell = between('pw.Widget _reportCell(', 'pw.Widget _reportTable(');
      expect(cell, isNot(contains('TextOverflow.clip')));
      expect(cell, isNot(contains('maxLines')));
    });

    test('the daily reports do not clip their cells either', () {
      final daily = File('lib/shared/pdf_export.dart').readAsStringSync();
      final cells = RegExp(
        r'pw\.Widget cell\(String text, \{required bool header\}\)[\s\S]*?\n        \);',
      ).allMatches(daily).toList();
      expect(cells.length, 2, reason: 'daily exits and daily entries');
      for (final c in cells) {
        expect(c.group(0), isNot(contains('TextOverflow.clip')));
        expect(c.group(0), isNot(contains('maxLines')));
      }
    });

    test('the period reads "من … إلى …", never an arrow', () {
      expect(periodLabel(DateTime(2026, 10, 8), DateTime(2026, 10, 8)), '2026/10/08');
      expect(periodLabel(DateTime(2026, 10, 8), DateTime(2026, 10, 10)),
          'من 2026/10/08 إلى 2026/10/10');
      for (final f in ['lib/shared/pdf_export.dart', 'lib/shared/pdf_export_period.dart', 'lib/shared/period_label.dart']) {
        expect(File(f).readAsStringSync(), isNot(contains('→ \${')), reason: f);
      }
    });
  });

  group('the PDF sources have no raw template text', () {
    // `\${` inside a Dart string prints the code itself ("${formatMoney(x)}")
    // instead of the number.
    for (final f in [
      'lib/shared/pdf_export.dart',
      'lib/shared/pdf_export_period.dart',
    ]) {
      test(f, () {
        final lines = File(f).readAsLinesSync();
        final bad = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(r'\${')) bad.add('${i + 1}: ${lines[i].trim()}');
        }
        expect(bad, isEmpty, reason: bad.join('\n'));
      });
    }
  });

  statementTitleChecks();

  group('the reports build', () {
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
      name: 'رافع المهدي',
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
        employeeName: 'رافع المهدي',
      );
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}

void statementTitleChecks() {
  test('the statement title names the account and the exchange company', () {
    final screen = File(
      'lib/features/companies/presentation/account_statement_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('كشف حساب \${companies[selected.companyId]?.name'));
    expect(screen, contains('لدى شركة \${selected.name}'));
    expect(screen, contains('title: Text(title)'));
  });
}
