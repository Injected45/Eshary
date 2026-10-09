import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/companies/domain/company.dart';
import 'package:eshary/features/companies/domain/exchange.dart';
import 'package:eshary/features/companies/presentation/accounts_screen.dart';
import 'package:eshary/features/companies/presentation/companies_providers.dart';
import 'package:eshary/features/currency_buy/domain/currency_buy.dart';
import 'package:eshary/features/currency_buy/presentation/currency_buys_providers.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/transfers/domain/transfer.dart';
import 'package:eshary/features/transfers/presentation/transfers_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing may start hidden behind the app bar (status bar + toolbar) or end
/// hidden behind the bottom bar, on a phone with a tall status bar.
void main() {
  final t0 = DateTime(2026, 1, 1);
  const statusBar = 44.0;
  const systemBottom = 34.0;
  const bottomBar = 96.0;
  var slowRefresh = false;

  Future<void> pumpInShell(WidgetTester tester, Widget body) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentEmployeeProvider.overrideWith((ref) async => null),
          companiesListProvider.overrideWith(
            (ref) async => [
              Company(
                id: 'c1',
                ownerId: 'o',
                name: 'الرحالة الأولى',
                startRef: 'A1',
                createdAt: t0,
              ),
            ],
          ),
          allExchangesProvider.overrideWith(
            (ref) async {
              if (slowRefresh) {
                await Future<void>.delayed(const Duration(seconds: 2));
              }
              return [
                Exchange(
                  id: 'e1',
                  companyId: 'c1',
                  name: 'بهار روز',
                  balance: 100,
                  ourCode: 'X',
                  country: null,
                  createdAt: t0,
                ),
              ];
            },
          ),
          exchangeCompaniesListProvider.overrideWith(
            (ref) async => [
              ExchangeCompany(
                id: 'x1',
                ownerId: 'o',
                name: 'بهار روز',
                createdAt: t0,
              ),
            ],
          ),
          archivedBuysProvider.overrideWith(
            (ref) async => [
              CurrencyBuy(
                id: 'b',
                ownerId: 'o',
                myCompanyId: 'c1',
                exchangeId: 'e1',
                clientId: null,
                clientFromAccount: null,
                usdAmount: 5,
                rate: 1,
                lydAmount: 5,
                reference: 'b',
                status: CurrencyBuyStatus.archived,
                createdAt: t0,
                archivedAt: t0,
                createdByEmployeeId: null,
              ),
            ],
          ),
          archivedTransfersProvider
              .overrideWith((ref) async => const <Transfer>[]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(
                top: statusBar,
                bottom: systemBottom,
              ),
            ),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            // Same shape as HomeShell: transparent app bar over the body,
            // floating bottom bar.
            child: Scaffold(
              extendBodyBehindAppBar: true,
              extendBody: true,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: AppBar(title: const Text('حساباتي')),
              ),
              body: body,
              bottomNavigationBar: const SizedBox(height: bottomBar),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('حساباتي: كشف حساب and الإلغاءات are fully below the app bar',
      (tester) async {
    await pumpInShell(tester, const AccountsScreen());
    const appBarBottom = statusBar + kToolbarHeight;
    for (final label in ['كشف حساب', 'الإلغاءات']) {
      final button = find.text(label);
      expect(button, findsOneWidget, reason: label);
      expect(
        tester.getRect(button).top,
        greaterThanOrEqualTo(appBarBottom),
        reason: '$label starts under the app bar',
      );
    }
  });

  test('no screen hard-codes the top or bottom inset any more', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        // A list padded by the toolbar height alone forgets the status bar.
        if (RegExp(r'(top: |\(16, )kToolbarHeight \+').hasMatch(l) ||
            RegExp(r'EdgeInsets\.fromLTRB\(16, \d+, 16, (32|40|96|120)\)')
                .hasMatch(l)) {
          offenders.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  testWidgets('حساباتي: the two buttons sit in a card; no تصفية button',
      (tester) async {
    await pumpInShell(tester, const AccountsScreen());
    final card = find.byKey(const ValueKey('accounts-actions'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('كشف حساب')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('الإلغاءات')),
      findsOneWidget,
    );
    expect(find.text('تصفية'), findsNothing);
  });

  testWidgets('حساباتي: the two buttons are the same width, centred',
      (tester) async {
    await pumpInShell(tester, const AccountsScreen());
    Rect rectOf(String label) => tester.getRect(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              )
              .first,
        );
    final a = rectOf('كشف حساب');
    final b = rectOf('الإلغاءات');
    expect(a.width, moreOrLessEquals(b.width, epsilon: 0.5));
    expect(a.top, moreOrLessEquals(b.top, epsilon: 0.5));
    // the pair sits in the middle: same margin on both sides of the screen
    const screenWidth = 360.0;
    final left = a.left < b.left ? a.left : b.left;
    final right = a.right > b.right ? a.right : b.right;
    expect(left, moreOrLessEquals(screenWidth - right, epsilon: 0.5));
  });

  // A background refresh (the 5-second poll, realtime) must not flash a
  // loading bar or blank the screen: the data stays until the new one arrives.
  testWidgets('a background refresh does not flash حساباتي', (tester) async {
    await pumpInShell(tester, const AccountsScreen());
    expect(find.text('كشف حساب'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountsScreen)),
    );
    slowRefresh = true;
    container.invalidate(allExchangesProvider);
    container.invalidate(companiesListProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // still refreshing: the old data is on screen, no loading bar
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('كشف حساب'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    slowRefresh = false;
    expect(find.text('كشف حساب'), findsOneWidget);
  });

  test('every async view keeps its data while it refreshes', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync().replaceAll('\r\n', '\n');
      for (final m
          in RegExp(r'\.when\(\n([^\n]*)\n([^\n]*)').allMatches(src)) {
        if (!m.group(1)!.contains('skipLoadingOnReload: true') ||
            !m.group(2)!.contains('skipError: true')) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      if (RegExp(r'Async\.isLoading\)').hasMatch(src) ||
          RegExp(r'Async\.isLoading \|\|').hasMatch(src)) {
        offenders.add('${f.path}: isLoading without hasValue');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
