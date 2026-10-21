import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/companies/presentation/no_account_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Exchange _ex(String name) => Exchange(
      id: name,
      companyId: 'c',
      name: name,
      balance: 100,
      ourCode: null,
      country: null,
      createdAt: DateTime(2026, 1, 1),
    );

Future<int> _open(
  WidgetTester tester,
  AsyncValue<List<Exchange>> exchanges,
  List<String> names,
) async {
  var loads = 0;
  await tester.binding.setSurfaceSize(const Size(420, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allExchangesProvider.overrideWith((ref) async {
          loads++;
          return <Exchange>[];
        }),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: NoAccountNotice(
              exchanges: exchanges,
              exchangeCompanyNames: names,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return loads;
}

Finder _k(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('no account at all: the usual advice', (tester) async {
    await _open(tester, const AsyncData(<Exchange>[]), ['بهار روز']);
    expect(_k('accounts-none'), findsOneWidget);
    expect(find.textContaining('أضف حساباً من تبويب حساباتي'), findsOneWidget);
  });

  testWidgets('accounts exist but their company is not in the list: says which',
      (tester) async {
    await _open(
      tester,
      AsyncData([_ex('بهار روز'), _ex('أنزار')]),
      ['بهار'],
    );
    expect(_k('accounts-unmatched'), findsOneWidget);
    expect(find.textContaining('لديك 2 حساب'), findsOneWidget);
    expect(find.textContaining('أنزار، بهار روز'), findsOneWidget);
    expect(find.textContaining('شركات الصرافة'), findsWidgets);
    expect(_k('accounts-none'), findsNothing,
        reason: 'it must not claim there is no account');
  });

  testWidgets('a failure to load is not "no account"', (tester) async {
    await _open(
      tester,
      AsyncError<List<Exchange>>(Exception('boom'), StackTrace.empty),
      ['بهار روز'],
    );
    expect(_k('accounts-load-failed'), findsOneWidget);
    expect(find.textContaining('تعذّر تحميل حساباتك'), findsOneWidget);
    expect(_k('accounts-none'), findsNothing);
  });

  testWidgets('the retry button asks for the accounts again', (tester) async {
    var loadsBefore = 0;
    loadsBefore = await _open(
      tester,
      AsyncError<List<Exchange>>(Exception('boom'), StackTrace.empty),
      ['x'],
    );
    expect(loadsBefore, 0);
    // the provider is only read once something listens: the retry invalidates it
    await tester.tap(_k('accounts-retry'));
    await tester.pump();
    expect(_k('accounts-retry'), findsOneWidget, reason: 'still showing');
  });
}
