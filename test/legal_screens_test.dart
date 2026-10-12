import 'dart:io';

import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/legal/data/account_deletion_repository.dart';
import 'package:eshary/features/legal/presentation/delete_account_screen.dart';
import 'package:eshary/features/legal/presentation/privacy_policy_screen.dart';
import 'package:eshary/features/trial/domain/trial_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDeletion implements AccountDeletionRepository {
  final calls = <String>[];
  bool wrongCode = false;

  @override
  Future<int> requestCode() async {
    calls.add('request');
    return 60;
  }

  @override
  Future<void> confirm(String code) async {
    calls.add('confirm:$code');
    if (wrongCode) throw const TrialRefused('invalid_code', left: 4);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('the privacy policy opens in the app, with the contact filled in',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PrivacyPolicyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('سياسة الخصوصية — تطبيق إشاري'), findsOneWidget);
    expect(find.text('الاحتفاظ والحذف'), findsOneWidget);
    expect(find.textContaining('{{SUPPORT}}'), findsNothing,
        reason: 'the placeholder is replaced');
    expect(find.textContaining('حذف حسابي'), findsWidgets);
  });

  test('the policy says what the app really does (no hidden collection)', () {
    final p = File('docs/privacy-policy.md').readAsStringSync();
    for (final must in [
      'رقم الهاتف',
      'لا نبيع بياناتك',
      'الإعدادات ثم «حذف حسابي»',
      'النسخ الاحتياطية',
      '{{SUPPORT}}',
    ]) {
      expect(p, contains(must), reason: must);
    }
    // nothing the app does not do is claimed
    for (final never in [
      'الموقع الجغرافي (GPS)',
      'الإعلانات المخصصة',
      'تتبع'
    ]) {
      expect(p.contains('نجمع $never'), isFalse);
    }
  });

  testWidgets('deleting the account: code first, then the final button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fake = _FakeDeletion();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: DeleteAccountScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // warned first, nothing is deleted by opening the screen
    expect(find.text('حذف الحساب نهائي'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-confirm')), findsNothing);
    expect(fake.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('delete-send-code')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['request']);
    // the destructive button appears only once a code was requested
    expect(find.byKey(const ValueKey('delete-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-field')), findsOneWidget);

    // an incomplete code deletes nothing
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['request']);
    expect(find.text('أدخل رمز واتساب المكوّن من 6 أرقام.'), findsOneWidget);
  });

  testWidgets('a wrong code is refused with the attempts left', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fake = _FakeDeletion()..wrongCode = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionRepositoryProvider.overrideWithValue(fake),
          supabaseClientProvider
              .overrideWith((ref) => throw UnimplementedError()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: DeleteAccountScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-send-code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('code-field')), '123456');
    await tester.pumpAndSettle();
    expect(fake.calls, ['request', 'confirm:123456']);
    expect(find.textContaining('متبقي 4 محاولة'), findsOneWidget);
  });

  test('settings: policy for everyone, deletion only for a subscriber', () {
    final s = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    expect(s, contains("title: 'سياسة الخصوصية'"));
    final del = s.substring(
        s.indexOf("title: 'حذف حسابي'") - 400, s.indexOf("title: 'حذف حسابي'"));
    expect(del, contains('!isAdmin'));
    expect(
        del.replaceAll(RegExp(r'\s+'), ' '), contains('isAnonymous != true'));
  });

  test('the privacy policy is reachable before signing in', () {
    final r = File('lib/core/router.dart').readAsStringSync();
    expect(r, contains("loc == '/privacy'"));
    final w = File('lib/features/auth/presentation/welcome_screen.dart')
        .readAsStringSync();
    expect(w, contains("ValueKey('welcome-privacy')"));
  });
}
