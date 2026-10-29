import 'package:eshary/core/theme.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/treasury/data/account_books_repository.dart';
import 'package:eshary/features/treasury/data/treasury_repository.dart';
import 'package:eshary/features/treasury/domain/account_books.dart';
import 'package:eshary/features/treasury/domain/lyd_treasury.dart';
import 'package:eshary/features/treasury/domain/profit_report.dart';
import 'package:eshary/features/treasury/domain/treasury_position.dart';
import 'package:eshary/features/treasury/presentation/opening_balances_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// «رصيد أول المدة» (0094). 1.0.14 kept its dinar part loading for ever: the
// summary was asked with a range ending at "now", a new provider key on
// every rebuild.

class _Treasury implements TreasuryRepository {
  _Treasury(this.summary);
  LydSummary summary;
  int summaries = 0;
  final calls = <String>[];

  @override
  Future<LydSummary> lydSummary(DateTime from, DateTime to) async {
    summaries++;
    return summary;
  }

  @override
  Future<void> lydOpen({required double cash, required double bank}) async =>
      calls.add('open $cash $bank');
  @override
  Future<void> lydMove({
    required String kind,
    String? pocket,
    required double amount,
    String? note,
    double? amountIn,
    String? requestId,
  }) async {}
  @override
  Future<LydCount> lydCount({
    required double counted,
    String? note,
    bool post = true,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<TreasuryPosition>> positions() async => const [];
  @override
  Future<void> setCost(String exchangeId, double rate, {String? book}) async {}
  @override
  Future<List<ProfitRow>> profitReport(DateTime from, DateTime to) async =>
      const [];
  @override
  Future<List<CostEvent>> costHistory(String exchangeId) async => const [];
}

class _Books implements AccountBooksRepository {
  _Books(this.rows);
  final List<AccountBooks> rows;
  final openings = <String>[];

  @override
  Future<List<AccountBooks>> list() async => rows;
  @override
  Future<void> setOpening({
    required String exchangeId,
    required String book,
    required double usd,
    required double cost,
  }) async =>
      openings.add('$exchangeId $book $usd $cost');
  @override
  Future<void> split({
    required String exchangeId,
    required double cashQty,
    double? cashCost,
    double? bankCost,
  }) async {}
  @override
  Future<void> move({
    required String exchangeId,
    required String from,
    required double usd,
    required double price,
    String? note,
    String? requestId,
  }) async {}
}

AccountBooks _account(String id, {double cash = 0, double? cashCost}) =>
    AccountBooks.fromJson({
      'exchange_id': id,
      'company_name': 'الرحالة',
      'account_name': 'حساب $id',
      'balance': cash,
      'split': true,
      'cash': {'balance': cash, 'cost_rate': cashCost},
      'bank': {'balance': 0, 'cost_rate': null},
    });

Future<void> _fonts() async {
  final loader = FontLoader('Almarai');
  for (final f in [
    'Almarai-Regular.ttf',
    'Almarai-Bold.ttf',
    'Almarai-ExtraBold.ttf',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/$f'));
  }
  await loader.load();
}

Future<void> _open(WidgetTester tester, _Treasury t, _Books b) async {
  await _fonts();
  await tester.binding.setSurfaceSize(const Size(400, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(t),
        accountBooksRepositoryProvider.overrideWithValue(b),
        isEmployeeProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: OpeningBalancesScreen(),
        ),
      ),
    ),
  );
  // a screen that reloads for ever never settles: this would time out
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the dinar part loads once and offers the opening',
      (tester) async {
    final t = _Treasury(LydSummary.fromJson(const {'open': false}));
    await _open(tester, t, _Books([_account('a1')]));
    expect(find.text('حفظ رصيد الدينار'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.summaries, lessThanOrEqualTo(2));
  });

  testWidgets('an opened treasury shows its opening figures', (tester) async {
    final t = _Treasury(LydSummary.fromJson(const {
      'open': true,
      'opening_cash': 5000,
      'opening_bank': 20000,
    }));
    await _open(tester, t, _Books([_account('a1')]));
    expect(find.text('حفظ رصيد الدينار'), findsNothing);
    expect(find.text('5,000.00 د.ل'), findsOneWidget);
  });

  testWidgets('an empty book takes its opening; a used one is shown',
      (tester) async {
    final t = _Treasury(LydSummary.fromJson(const {'open': false}));
    final b = _Books([_account('a1'), _account('a2', cash: 100, cashCost: 7)]);
    await _open(tester, t, b);
    // a1: both books open; a2: its bank book only
    expect(find.text('حفظ رصيد أول المدة'), findsNWidgets(2));
    // the used book shows what it holds instead of fields
    expect(find.textContaining('\$100.00 ×'), findsOneWidget);
  });
}
