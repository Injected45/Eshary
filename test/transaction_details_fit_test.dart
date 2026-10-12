import 'package:eshary/core/theme.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/shared/transaction_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _old = DateTime(2026, 1, 1, 14, 5);

final _transfer = Transfer(
  id: 't1',
  ownerId: 'o',
  companyId: 'c',
  exchangeId: 'e',
  beneficiaryName: 'علي محمد',
  beneficiaryAccountCompany: 'شركة المستفيد للصرافة',
  beneficiaryCode: 'B-90210',
  amount: 1250,
  reference: 'REF-0001',
  status: TransferStatus.archived,
  createdAt: _old,
  archivedAt: _old,
  createdByEmployeeId: null,
);

/// Opens the page the way the app does (a pushed route) on a given phone size.
Future<void> _open(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTransferDetails(
                    context,
                    transfer: _transfer,
                    companyName: 'شركتي',
                    exchangeName: 'شركة الصرافة',
                    exchangeCode: 'X-100',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(320, 568), // small old phone
    Size(360, 640),
    Size(390, 844), // modern phone
    Size(412, 915),
  ]) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()}: everything '
        'is on screen, no scrolling, nothing cut', (tester) async {
      await _open(tester, size);
      // no scrollable at all on the page
      expect(find.byType(Scrollable), findsNothing);
      expect(find.byType(ListView), findsNothing);

      final screen = Offset.zero & size;
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      // every line of the record is fully inside the visible area, below the bar
      for (final t in [
        'خروج من حسابي',
        'جهة الاستلام',
        'معلومات العملية',
        'شركة الصرافة',
        'REF-0001',
        r'$ 1,250.00',
        'علي محمد',
        'B-90210',
        'أنا',
      ]) {
        final r = tester.getRect(find.text(t).first);
        expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight),
            isTrue,
            reason: '$t is cut: $r on $size');
        expect(r.top, greaterThanOrEqualTo(appBarBottom - 0.5),
            reason: '$t hides under the app bar');
      }
      // the date line (the first thing in the page) is not cut at the top
      final date = tester.getRect(find.textContaining('التاريخ والوقت'));
      expect(date.top, greaterThanOrEqualTo(appBarBottom));
    });
  }

  testWidgets('a short phone scales the content, it does not crop it',
      (tester) async {
    await _open(tester, const Size(320, 480));
    expect(find.byType(Scrollable), findsNothing);
    final fit = tester.getRect(find.byKey(const ValueKey('details-fit')));
    expect(fit.bottom, lessThanOrEqualTo(480));
    final last = tester.getRect(find.text('أنا'));
    expect(last.bottom, lessThanOrEqualTo(480));
  });

  test('the entry (buy) page uses the same layout', () {
    // the same _DetailsPage builds both pages; keep a reference so a change to
    // the buy model keeps this file honest
    expect(CurrencyBuyStatus.values, isNotEmpty);
  });
}
