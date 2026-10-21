import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/clients/data/clients_repository.dart';
import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/clients/presentation/clients_providers.dart';
import 'package:eshary/features/clients/presentation/delete_party.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Client _p(String id, String name, String? company) => Client(
      id: id,
      ownerId: 'u',
      name: name,
      company: company,
      code: null,
      createdAt: DateTime(2026, 1, 1),
    );

ExchangeCompany _ec(String name, String kind) => ExchangeCompany(
      id: name,
      ownerId: 'u',
      name: name,
      createdAt: DateTime(2026, 1, 1),
      kind: kind,
    );

class _FakeRepo implements ClientsRepository {
  final deleted = <String>[];
  String? removedCompany;
  Object? failWith;

  @override
  Future<String?> delete(String id) async {
    if (failWith != null) throw failWith!;
    deleted.add(id);
    return removedCompany;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('which company goes with a deleted party', () {
    final all = [
      _p('1', 'أ', 'شركة س'),
      _p('2', 'ب', 'شركة ص'),
      _p('3', 'ج', 'شركة ص'),
      _p('4', 'د', null),
    ];
    const clientCompanies = ['شركة س', 'شركة ص'];

    test('its own company, when no other party uses it', () {
      expect(companyThatGoesWith(all[0], all, clientCompanies), 'شركة س');
    });

    test('not when another party uses it too', () {
      expect(companyThatGoesWith(all[1], all, clientCompanies), isNull);
    });

    test('a party with no company: nothing', () {
      expect(companyThatGoesWith(all[3], all, clientCompanies), isNull);
    });

    test('a company that is not a customer\'s (mine) never goes', () {
      expect(companyThatGoesWith(all[0], all, const ['شركة ص']), isNull);
    });
  });

  group('the delete dialog', () {
    Future<(_FakeRepo, BuildContext)> open(
      WidgetTester tester,
      Client party,
      List<Client> all,
    ) async {
      await tester.binding.setSurfaceSize(const Size(450, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fake = _FakeRepo();
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientsRepositoryProvider.overrideWithValue(fake),
            clientsListProvider.overrideWith((ref) async => all),
            exchangeCompaniesListProvider.overrideWith(
              (ref) async => [
                _ec('شركة س', kExchangeCompanyClient),
                _ec('شركة ص', kExchangeCompanyClient),
                _ec('بهاروز', kExchangeCompanyMine),
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Center(
                    child: TextButton(
                      onPressed: () {
                        ctx = context;
                        confirmAndDeleteParty(context, ref, party);
                      },
                      child: const Text('احذف'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('احذف'));
      await tester.pumpAndSettle();
      return (fake, ctx);
    }

    testWidgets('it says the company goes too, and does both on confirm',
        (tester) async {
      final all = [_p('1', 'أ', 'شركة س'), _p('2', 'ب', 'شركة ص')];
      final (fake, _) = await open(tester, all[0], all);
      expect(find.byKey(const ValueKey('delete-party-what')), findsOneWidget);
      expect(find.textContaining('شركة «شركة س»'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-party-company-kept')),
          findsNothing);
      fake.removedCompany = 'شركة س';
      await tester.tap(find.byKey(const ValueKey('delete-party-confirm')));
      await tester.pumpAndSettle();
      expect(fake.deleted, ['1']);
      expect(
          find.textContaining('تم حذف الجهة وشركتها «شركة س»'), findsOneWidget);
    });

    testWidgets('it says the company stays when another party uses it',
        (tester) async {
      final all = [_p('2', 'ب', 'شركة ص'), _p('3', 'ج', 'شركة ص')];
      await open(tester, all[0], all);
      expect(find.byKey(const ValueKey('delete-party-company')), findsNothing);
      expect(find.byKey(const ValueKey('delete-party-company-kept')),
          findsOneWidget);
      expect(find.textContaining('تبقى شركة «شركة ص»'), findsOneWidget);
    });

    testWidgets('cancel deletes nothing', (tester) async {
      final all = [_p('1', 'أ', 'شركة س')];
      final (fake, _) = await open(tester, all[0], all);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(fake.deleted, isEmpty);
    });

    testWidgets('a party with operations is refused in plain Arabic',
        (tester) async {
      final all = [_p('1', 'أ', 'شركة س')];
      final (fake, _) = await open(tester, all[0], all);
      fake.failWith = Exception('client_has_operations');
      await tester.tap(find.byKey(const ValueKey('delete-party-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('لارتباطها بعمليات مالية'), findsOneWidget);
    });
  });

  test('the server errors read in plain Arabic', () {
    expect(friendlyError('company_in_use_accounts'), contains('لك حساب عندها'));
    expect(friendlyError('company_in_use_parties'), contains('جهات محفوظة'));
    expect(friendlyError('party_not_found'), contains('لم تعد موجودة'));
  });

  test('both places that delete a party use the same cleanup', () {
    for (final f in [
      'lib/features/clients/presentation/saved_clients_dialog.dart',
      'lib/features/clients/presentation/clients_screen.dart',
    ]) {
      final s = File(f).readAsStringSync();
      expect(s, contains('confirmAndDeleteParty('), reason: f);
      expect(s.contains('clientsRepositoryProvider).delete('), isFalse,
          reason: '$f must not delete behind the helper');
    }
    final repo = File('lib/features/clients/data/clients_repository.dart')
        .readAsStringSync();
    expect(repo, contains("'delete_party'"));
    final sql = File('supabase/migrations/0075_delete_party_cleanly.sql')
        .readAsStringSync();
    expect(sql, contains('function delete_party'));
    expect(sql, contains('company_in_use_accounts'));
    expect(sql, contains('company_in_use_parties'));
  });
}
