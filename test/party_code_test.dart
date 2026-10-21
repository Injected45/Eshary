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
import 'package:eshary/features/sub_users/domain/employee_permissions.dart';
import 'package:eshary/features/exchange_companies/presentation/exchange_companies_providers.dart';
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

ExchangeCompany _company(String id, String name) => ExchangeCompany(
      id: id,
      ownerId: 'u1',
      name: name,
      createdAt: DateTime(2026, 10, 1),
      // the customer dialog offers customers' companies only (0074)
      kind: kExchangeCompanyClient,
    );

class _FakeClients implements ClientsRepository {
  final created = <Map<String, String?>>[];

  @override
  Future<Client> create({
    required String ownerId,
    required String name,
    String? company,
    String? code,
    String? refPrefix,
  }) async {
    created.add({
      'name': name,
      'company': company,
      'code': code,
      if ((refPrefix ?? '').isNotEmpty) 'ref': refPrefix,
    });
    return _client('new', name, company, code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _saved = [
  _client('1', 'تاجر الأول', 'بهار روز', '5521'),
  _client('2', 'تاجر الثاني', 'أنزار', '7788'),
];

Future<_FakeClients> _openAdd(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = _FakeClients();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientsRepositoryProvider.overrideWithValue(fake),
        clientsListProvider.overrideWith((ref) async => _saved),
        exchangeCompaniesListProvider.overrideWith(
          (ref) async => [_company('c1', 'بهار روز'), _company('c2', 'أنزار')],
        ),
        currentUserIdProvider.overrideWithValue('u1'),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AddClientDialog(onSaved: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _chooseCompany(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  group('comparing codes', () {
    test('digits, spaces and case do not make a different code', () {
      expect(partyKey('٥٥٢١'), '5521');
      expect(partyKey(' 55 21 '), '5521');
      expect(partyKey('Ab12'), 'ab12');
      expect(partyKey(null), '');
      expect(partyKey('بهار  روز'), partyKey('بهار روز'));
    });

    test('a stored code keeps its case and its leading zeros', () {
      expect(cleanCode(' ٠٠٥٥٢١ '), '005521');
      expect(cleanCode('Ab 12'), 'Ab12');
    });

    test('the same code at two companies is two parties', () {
      final a = _client('1', 'أ', 'بهار روز', '5521');
      final b = _client('2', 'ب', 'أنزار', '5521');
      bool same(Client x, Client y) =>
          partyKey(x.code) == partyKey(y.code) &&
          partyKey(x.company) == partyKey(y.company);
      expect(same(a, b), isFalse);
      expect(same(a, _client('3', 'ج', 'بهار  روز', '٥٥٢١')), isTrue);
    });
  });

  group('finding a party', () {
    test('by its code first, by name or company too', () {
      expect(filterParties(_saved, '5521').map((c) => c.id), ['1']);
      expect(filterParties(_saved, '٧٧٨٨').map((c) => c.id), ['2']);
      expect(filterParties(_saved, 'أنزار').map((c) => c.id), ['2']);
      expect(filterParties(_saved, 'الأول').map((c) => c.id), ['1']);
      expect(filterParties(_saved, '   '), _saved);
      expect(filterParties(_saved, '999'), isEmpty);
    });

    test('a row shows the company and the code', () {
      expect(partySubtitle(_saved.first), 'بهار روز · كود 5521');
      expect(partySubtitle(_client('9', 'س', null, null)), '—');
      expect(partySubtitle(_client('9', 'س', 'أنزار', '')), 'أنزار');
    });

    testWidgets('the list has a search box that narrows it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientsListProvider.overrideWith((ref) async => _saved),
            isEmployeeProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: SavedClientsDialog()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('تاجر الأول'), findsOneWidget);
      expect(find.text('تاجر الثاني'), findsOneWidget);
      expect(find.text('بهار روز · كود 5521'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('party-search')), '7788');
      await tester.pumpAndSettle();
      expect(find.text('تاجر الأول'), findsNothing);
      expect(find.text('تاجر الثاني'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('party-search')), '000');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد جهة بهذا الكود أو الاسم'), findsOneWidget);
    });
  });

  group('saving a party', () {
    testWidgets('a code alone is enough: the party is called by its code',
        (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'بهار روز');
      await tester.enterText(_field('كود الحساب'), '9001');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'كود 9001', 'company': 'بهار روز', 'code': '9001'},
      ]);
    });

    testWidgets(
        'the same code on the same company is refused, naming the owner',
        (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'بهار روز');
      await tester.enterText(_field('كود الحساب'), '5521');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, isEmpty);
      expect(
        find.textContaining('هذا الكود مسجّل مسبقًا على نفس الشركة'),
        findsOneWidget,
      );
      expect(find.textContaining('تاجر الأول'), findsOneWidget);
    });

    testWidgets('Arabic digits and spaces are the same code', (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'بهار روز');
      await tester.enterText(_field('كود الحساب'), ' ٥٥ ٢١ ');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, isEmpty);
      expect(find.textContaining('مسجّل مسبقًا'), findsOneWidget);
    });

    testWidgets('the same code on another company is another party',
        (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'أنزار');
      await tester.enterText(_field('كود الحساب'), '5521');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'كود 5521', 'company': 'أنزار', 'code': '5521'},
      ]);
    });

    testWidgets('a typed name is kept; and the code is stored clean',
        (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'أنزار');
      await tester.enterText(_field('كود الحساب'), '٣٣٠٠');
      await tester.enterText(_field('اسم العميل'), 'محمد');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'محمد', 'company': 'أنزار', 'code': '3300'},
      ]);
    });

    testWidgets('nothing typed: asks for a code, a name or a company',
        (tester) async {
      final fake = await _openAdd(tester);
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, isEmpty);
      expect(
          find.text(
              'اكتب أي حقل واحد على الأقل: الشركة أو الكود أو الاسم أو حروف الإشاري'),
          findsOneWidget);
    });

    testWidgets('a merchant with account name + code and no company is saved',
        (tester) async {
      final fake = await _openAdd(tester);
      await tester.enterText(_field('كود الحساب'), '7001');
      await tester.enterText(_field('اسم العميل'), 'ابوبكر');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'ابوبكر', 'company': null, 'code': '7001'},
      ]);
    });

    testWidgets('a company alone is enough: the party takes its name',
        (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'أنزار');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'أنزار', 'company': 'أنزار', 'code': ''},
      ]);
    });

    test('a row shows what the merchant gave: no dash before a lone code', () {
      expect(partySubtitle(_client('9', 'س', null, '5521')), 'كود 5521');
      expect(partySubtitle(_client('9', 'س', 'أنزار', '5521')),
          'أنزار · كود 5521');
    });

    // Any ONE of the four fields is enough to save a party.
    testWidgets('only the reference letters: saved, named by them',
        (tester) async {
      final fake = await _openAdd(tester);
      await tester.enterText(find.byKey(const ValueKey('ref-prefix')), 'TRC');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'TRC', 'company': null, 'code': '', 'ref': 'TRC'},
      ]);
    });

    testWidgets('only the name: saved', (tester) async {
      final fake = await _openAdd(tester);
      await tester.enterText(_field('اسم العميل'), 'ابوبكر');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'ابوبكر', 'company': null, 'code': ''},
      ]);
    });

    testWidgets('only the code: saved as "كود …"', (tester) async {
      final fake = await _openAdd(tester);
      await tester.enterText(_field('كود الحساب'), '8123');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {'name': 'كود 8123', 'company': null, 'code': '8123'},
      ]);
    });

    testWidgets('the same letters-only party twice is refused', (tester) async {
      final fake = await _openAdd(tester);
      await tester.enterText(find.byKey(const ValueKey('ref-prefix')), 'ZZZ');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created.length, 1);
    });

    test('a row shows the letters too', () {
      Client c(String? company, String? code, String? letters) => Client(
            id: '1',
            ownerId: 'u',
            name: 'x',
            company: company,
            code: code,
            createdAt: DateTime(2026, 1, 1),
            refPrefix: letters,
          );
      expect(partySubtitle(c(null, null, 'TRC')), 'إشاري TRC');
      expect(partySubtitle(c('أنزار', '5521', 'TRC')),
          'أنزار · كود 5521 · إشاري TRC');
      expect(partySubtitle(c(null, null, null)), '—');
    });

    testWidgets('the fields run company, code, name', (tester) async {
      await _openAdd(tester);
      final company =
          tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dy;
      final code = tester.getTopLeft(_field('كود الحساب')).dy;
      final name = tester.getTopLeft(_field('اسم العميل')).dy;
      expect(company, lessThan(code));
      expect(code, lessThan(name));
    });
  });

  test('no transfer message prints an empty account-name line', () {
    final src =
        File('lib/features/transfers/presentation/transfers_screen.dart')
            .readAsStringSync();
    // the three messages show the account name only when there is one
    expect(src.split("bank.isEmpty ? '' : 'في حساب").length - 1, 1);
    expect(src.split("bank.isEmpty ? '' : 'إسم الحساب").length - 1, 2);
    // and never as a bare line
    expect(
      RegExp(r"^\s*'إسم الحساب : \$bank", multiLine: true).hasMatch(src),
      isFalse,
    );
  });

  test(
      'the entry messages leave out the account line for a sender with no name',
      () {
    final src =
        File('lib/features/currency_buy/presentation/currency_buy_screen.dart')
            .readAsStringSync();
    expect(src.split("senderAccount.isEmpty ? '' : 'حساب").length - 1, 2);
    expect(src.contains("nameForCode((_client?.code ?? '').trim())"), isTrue);
    expect(
      RegExp(r"^\s*'حساب : \$senderAccount", multiLine: true).hasMatch(src),
      isFalse,
    );
  });

  group('a sender with fixed reference letters', () {
    test('only the number is typed: TRC + 185 is TRC185', () {
      expect(fullReference('TRC', '185'), 'TRC185');
      expect(fullReference('TRC', ' 250 '), 'TRC250');
      expect(fullReference(' TRC ', '300'), 'TRC300');
    });

    test('nothing typed is no reference, even with letters', () {
      expect(fullReference('TRC', ''), '');
      expect(fullReference('TRC', '   '), '');
    });

    test('a sender with no letters keeps the typed reference as it is', () {
      expect(fullReference(null, 'R-1'), 'R-1');
      expect(fullReference('', 'R-1'), 'R-1');
    });

    test('the letters are not doubled when typed again', () {
      expect(fullReference('TRC', 'TRC185'), 'TRC185');
      expect(fullReference('TRC', 'trc185'), 'trc185');
    });

    test('the party carries them from the database', () {
      final c = Client.fromJson({
        'id': '1',
        'owner_id': 'u1',
        'name': 'x',
        'company': 'أنزار',
        'code': '5551',
        'created_at': '2026-10-01T00:00:00Z',
        'ref_prefix': 'TRC',
      });
      expect(c.refPrefix, 'TRC');
      expect(_client('2', 'y', null, null).refPrefix, isNull);
    });

    testWidgets('the dialog saves the letters with the party', (tester) async {
      final fake = await _openAdd(tester);
      await _chooseCompany(tester, 'أنزار');
      await tester.enterText(_field('كود الحساب'), '5551');
      await tester.enterText(find.byKey(const ValueKey('ref-prefix')), ' TRC ');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(fake.created, [
        {
          'name': 'كود 5551',
          'company': 'أنزار',
          'code': '5551',
          'ref': ' TRC '
        },
      ]);
    });

    test('the entry form records the letters + number, and the message too',
        () {
      final src = File(
              'lib/features/currency_buy/presentation/currency_buy_screen.dart')
          .readAsStringSync();
      expect(src.split('reference: _fullReference,').length - 1, 2);
      expect(src.contains('final reference = _fullReference;'), isTrue);
      expect(src.contains('reference: _reference.text.trim()'), isFalse);
      expect(src.contains('prefixText: _refPrefix.isEmpty ? null : _refPrefix'),
          isTrue);
    });

    test('0069 adds the column, and an update leaves the letters alone', () {
      final sql = File('supabase/migrations/0069_party_reference_prefix.sql')
          .readAsStringSync();
      expect(sql, contains('add column if not exists ref_prefix'));
      final repo = File('lib/features/clients/data/clients_repository.dart')
          .readAsStringSync();
      expect(repo, contains('if (updateRefPrefix)'));
    });
  });

  test('a missing code is left out of the messages, not printed empty', () {
    final buy =
        File('lib/features/currency_buy/presentation/currency_buy_screen.dart')
            .readAsStringSync();
    expect(buy.split("senderCode.isEmpty ? '' : ").length - 1, 2);
    expect(buy.contains('(_senderCodeStored || _senderCodeTyped'), isFalse);
    final out =
        File('lib/features/transfers/presentation/transfers_screen.dart')
            .readAsStringSync();
    expect(out.split("benCode.isEmpty ? '' : ").length - 1, 3);
    // our own account code too: nothing is printed for what is not written
    expect(out.split("code.isEmpty ? '' : '🔢 كود : ").length - 1, 3);
    expect(buy.split("myCode.isEmpty ? '' : ").length - 1, 2);
  });

  test('a missing company is left out of the messages too', () {
    final buy =
        File('lib/features/currency_buy/presentation/currency_buy_screen.dart')
            .readAsStringSync();
    expect(buy.split("senderCompany.isEmpty ? '' : ").length - 1, 2);
    final out =
        File('lib/features/transfers/presentation/transfers_screen.dart')
            .readAsStringSync();
    expect(out.split("beneficiary.isEmpty ? '' : ").length - 1, 3);
  });

  test('no reference: the lines are left out and the save does not wait', () {
    final buy =
        File('lib/features/currency_buy/presentation/currency_buy_screen.dart')
            .readAsStringSync();
    expect(buy.contains(r"reference.isEmpty ? '' : 'اشاري ( $reference )"),
        isTrue);
    expect(
        buy.contains(r"reference.isEmpty ? '' : 'الرقم الإشاري : $reference"),
        isTrue);
    expect(
        buy.replaceAll(RegExp(r'\s+'), ' '),
        contains(
            'bool get _readyToSave => _accountComplete && _senderSaveable;'));
    final out =
        File('lib/features/transfers/presentation/transfers_screen.dart')
            .readAsStringSync();
    expect(out.split("ref.isEmpty ? '' : '📄 الرقم الإشاري").length - 1, 3);
  });

  test('a party can be edited (letters included) from the saved list', () {
    final list =
        File('lib/features/clients/presentation/saved_clients_dialog.dart')
            .readAsStringSync();
    expect(list, contains("ValueKey('party-edit-"));
    expect(list, contains('existing: item'));
  });

  group('the pencil as a permission', () {
    test('an employee can be granted it, and it is described', () {
      final p =
          kEmployeePermissions.firstWhere((p) => p.key == kPermPartyLetters);
      expect(p.key, 'party_letters');
      expect(p.label, contains('حروف'));
      expect(p.description, contains('لا يستطيع تغيير أي شيء آخر'));
    });

    test('the pencil follows the permission; the administrator always has it',
        () {
      final src = File(
              'lib/features/currency_buy/presentation/currency_buy_screen.dart')
          .readAsStringSync();
      expect(src, contains('!ref.watch(canProvider(kPermPartyLetters))'));
      // an employee opens only the letters, the administrator the whole party
      expect(src, contains('showPartyLettersDialog('));
      expect(src, contains('setPartyLetters(c.id, letters)'));
    });

    test('the server checks the permission, the owner and the length', () {
      final sql = File('supabase/migrations/0071_party_letters_permission.sql')
          .readAsStringSync();
      expect(sql, contains("employee_has_perm('party_letters')"));
      expect(sql, contains('owner_id = v_parent'));
      expect(sql, contains('letters_too_long'));
    });
  });

  test('the database refuses it too, and the error is in plain Arabic', () {
    final sql = File('supabase/migrations/0068_party_code_unique.sql')
        .readAsStringSync();
    expect(sql, contains('clients_owner_company_code_uq'));
    expect(sql, contains('_party_key(company)'));
    expect(sql, contains('_party_key(code)'));
    final log = File('lib/shared/logger.dart').readAsStringSync();
    expect(log, contains('clients_owner_company_code_uq'));
  });
}
