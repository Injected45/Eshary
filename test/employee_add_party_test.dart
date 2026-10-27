import 'dart:io';

import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/clients/data/clients_repository.dart';
import 'package:eshary/features/clients/domain/client.dart';
import 'package:eshary/features/clients/presentation/add_client_dialog.dart';
import 'package:eshary/features/clients/presentation/clients_providers.dart';
import 'package:eshary/features/clients/presentation/saved_clients_dialog.dart';
import 'package:eshary/features/employee_auth/presentation/employee_auth_providers.dart';
import 'package:eshary/features/exchange_companies/domain/exchange_company.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
import 'package:eshary/features/sub_users/domain/employee_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Client _client(String id, String name, String? company, String? code) => Client(
      id: id,
      ownerId: 'u1',
      name: name,
      company: company,
      code: code,
      createdAt: DateTime(2026, 10, 1),
    );

class _Fake implements ClientsRepository {
  final byEmployee = <Map<String, String?>>[];
  final byAdmin = <Map<String, String?>>[];

  @override
  Future<Client> create({
    required String ownerId,
    required String name,
    String? company,
    String? code,
    String? refPrefix,
  }) async {
    byAdmin.add({'name': name, 'company': company, 'code': code});
    return _client('new', name, company, code);
  }

  @override
  Future<Client> createAsEmployee({
    required String name,
    String? company,
    String? code,
    String? refPrefix,
  }) async {
    byEmployee.add({'name': name, 'company': company, 'code': code});
    return _client('new', name, company, code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _saved = [_client('1', 'تاجر الأول', 'بهار روز', '5521')];

List<Override> _overrides(_Fake fake,
        {required bool employee, bool can = false}) =>
    [
      clientsRepositoryProvider.overrideWithValue(fake),
      clientsListProvider.overrideWith((ref) async => _saved),
      exchangeCompaniesListProvider.overrideWith(
        (ref) async => [
          ExchangeCompany(
            id: 'c1',
            ownerId: 'u1',
            name: 'بهار روز',
            createdAt: DateTime(2026, 10, 1),
            kind: kExchangeCompanyClient,
          ),
        ],
      ),
      currentUserIdProvider.overrideWithValue('u1'),
      isEmployeeProvider.overrideWithValue(employee),
      canProvider(kPermClientsAdd).overrideWithValue(can),
    ];

Future<void> _pump(WidgetTester tester, Widget body, List<Override> o) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: o,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: body),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the add dialog for an employee', () {
    testWidgets('saves through the employee call, not a direct insert', (
      tester,
    ) async {
      final fake = _Fake();
      await _pump(
        tester,
        AddClientDialog(onSaved: () {}),
        _overrides(fake, employee: true, can: true),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'اسم العميل'),
        'عميل الموظف',
      );
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.byEmployee.map((m) => m['name']), ['عميل الموظف']);
      expect(fake.byAdmin, isEmpty);
    });

    testWidgets('has no button to create an exchange company', (tester) async {
      await _pump(
        tester,
        AddClientDialog(onSaved: () {}),
        _overrides(_Fake(), employee: true, can: true),
      );
      expect(find.text('إضافة شركة جديدة'), findsNothing);
    });

    testWidgets(
        'the administrator keeps the direct insert and the company button',
        (tester) async {
      final fake = _Fake();
      await _pump(
        tester,
        AddClientDialog(onSaved: () {}),
        _overrides(fake, employee: false),
      );
      expect(find.text('إضافة شركة جديدة'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'اسم العميل'),
        'عميل المدير',
      );
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.byAdmin.map((m) => m['name']), ['عميل المدير']);
      expect(fake.byEmployee, isEmpty);
    });
  });

  group('the saved parties list', () {
    Finder add() => find.byKey(const ValueKey('party-add'));

    testWidgets('an employee without the permission has no add button', (
      tester,
    ) async {
      await _pump(
        tester,
        const SavedClientsDialog(),
        _overrides(_Fake(), employee: true, can: false),
      );
      expect(add(), findsNothing);
    });

    testWidgets(
        'an employee with it gets the add button, but no edit or delete',
        (tester) async {
      await _pump(
        tester,
        const SavedClientsDialog(),
        _overrides(_Fake(), employee: true, can: true),
      );
      expect(add(), findsOneWidget);
      expect(find.byKey(const ValueKey('party-edit-1')), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('the beneficiaries list (exit screen) follows the same rule', (
      tester,
    ) async {
      await _pump(
        tester,
        const SavedClientsDialog(config: SavedEntitiesConfig.beneficiaries),
        _overrides(_Fake(), employee: true, can: true),
      );
      expect(add(), findsOneWidget);
    });

    testWidgets('the administrator always has it', (tester) async {
      await _pump(
        tester,
        const SavedClientsDialog(),
        _overrides(_Fake(), employee: false),
      );
      expect(add(), findsOneWidget);
      expect(find.byKey(const ValueKey('party-edit-1')), findsOneWidget);
    });
  });

  group('the permission and the entry screen', () {
    test('the administrator can grant it from the permissions list', () {
      final p =
          kEmployeePermissions.firstWhere((p) => p.key == kPermClientsAdd);
      expect(p.key, 'clients_add');
      expect(p.label, 'إضافة جهات محفوظة');
    });

    test('the entry screen offers an add button to such an employee', () {
      final src = File(
        'lib/features/currency_buy/presentation/currency_buy_screen.dart',
      ).readAsStringSync();
      expect(src, contains("ValueKey('employee-add-party')"));
      expect(src, contains('canProvider(kPermClientsAdd)'));
    });

    test('the database call is the only write path', () {
      final repo = File('lib/features/clients/data/clients_repository.dart')
          .readAsStringSync();
      expect(repo, contains("'employee_add_party'"));
      final sql = File('supabase/migrations/0078_employee_add_party.sql')
          .readAsStringSync();
      expect(sql, contains("employee_has_perm('clients_add')"));
      expect(sql, contains('v_parent'));
    });
  });
}
