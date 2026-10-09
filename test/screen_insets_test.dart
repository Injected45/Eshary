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
            (ref) async => [
              Exchange(
                id: 'e1',
                companyId: 'c1',
                name: 'بهار روز',
                balance: 100,
                ourCode: 'X',
                country: null,
                createdAt: t0,
              ),
            ],
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
}
