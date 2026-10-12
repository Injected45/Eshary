import 'dart:io';

import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/legal/data/account_deletion_repository.dart';
import 'package:eshary/features/legal/presentation/delete_account_screen.dart';
import 'package:eshary/features/legal/presentation/privacy_policy_screen.dart';
import 'package:eshary/features/trial/domain/trial_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

/// The legal screens inside a real router, as in the app. `/` is the main
/// screen the back arrow has to reach.
Future<GoRouter> _openLegal(WidgetTester tester, String start) async {
  await tester.binding.setSurfaceSize(const Size(400, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // the asset bundle caches the loading future of an earlier test's zone
  rootBundle.evict(kPrivacyPolicyAsset);
  rootBundle.evict(kTermsOfUseAsset);
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('الشاشة الرئيسية'),
                TextButton(
                  onPressed: () => context.push('/terms'),
                  child: const Text('افتح الشروط'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
          path: '/privacy', builder: (_, __) => const PrivacyPolicyScreen()),
      GoRoute(path: '/terms', builder: (_, __) => const TermsOfUseScreen()),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildAppTheme(),
      builder: (_, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('the privacy policy opens in the app, with the contact filled in',
      (tester) async {
    await _openLegal(tester, '/privacy');
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
    // pushed (not replaced), so there is a screen to go back to
    expect(w, contains("context.push('/privacy')"));
    expect(w, contains("context.push('/terms')"));
  });

  testWidgets('the terms of use open in the app, with the contact filled in',
      (tester) async {
    await _openLegal(tester, '/terms');
    expect(find.text('شروط استخدام تطبيق إشاري'), findsOneWidget);
    expect(find.text('التجربة والاشتراك'), findsOneWidget);
    expect(find.textContaining('{{SUPPORT}}'), findsNothing);
  });

  testWidgets(
      'opened as the only screen (welcome link), the arrow returns to the main screen',
      (tester) async {
    await _openLegal(tester, '/terms');
    expect(find.byKey(const ValueKey('legal-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legal-back')));
    await tester.pumpAndSettle();
    expect(find.text('الشاشة الرئيسية'), findsOneWidget);
    expect(find.text('شروط استخدام تطبيق إشاري'), findsNothing);
  });

  testWidgets('the phone back button does the same, instead of closing the app',
      (tester) async {
    await _openLegal(tester, '/privacy');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('الشاشة الرئيسية'), findsOneWidget);
    expect(find.text('سياسة الخصوصية — تطبيق إشاري'), findsNothing);
  });

  testWidgets('opened from a screen (Settings), the arrow goes back to it',
      (tester) async {
    await _openLegal(tester, '/');
    await tester.tap(find.text('افتح الشروط'));
    await tester.pumpAndSettle();
    expect(find.text('شروط استخدام تطبيق إشاري'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legal-back')));
    await tester.pumpAndSettle();
    expect(find.text('الشاشة الرئيسية'), findsOneWidget);
    expect(find.text('شروط استخدام تطبيق إشاري'), findsNothing);
  });

  test('the terms say what the app really is and does', () {
    final t = File('docs/terms-of-use.md').readAsStringSync();
    for (final must in [
      'لا ينفّذ تحويل الأموال',
      'لكل رقم هاتف تجربة واحدة',
      'وقت الخادم',
      'بقيد عكسي',
      'حذف حسابي',
      '{{SUPPORT}}',
    ]) {
      expect(t, contains(must), reason: must);
    }
  });

  test(
      'the terms are read before and after signing in, and agreed to with the request',
      () {
    final r = File('lib/core/router.dart').readAsStringSync();
    expect(r, contains("loc == '/terms'"));
    // a signed-in user must reach them from Settings: they are NOT treated as
    // sign-in screens (those send a signed-in user back to the home page)
    final signIn = r.substring(
        r.indexOf('final atAdminAuth ='), r.indexOf('final atEmployeeAuth ='));
    expect(signIn.contains('/privacy'), isFalse);
    expect(signIn.contains('/terms'), isFalse);
    expect(
        r, contains("if (loc == '/privacy' || loc == '/terms') return null;"));
    expect(
        File('lib/features/auth/presentation/welcome_screen.dart')
            .readAsStringSync(),
        contains("ValueKey('welcome-terms')"));
    expect(
        File('lib/features/settings/presentation/settings_screen.dart')
            .readAsStringSync(),
        contains("title: 'شروط الاستخدام'"));
    final form =
        File('lib/features/trial/presentation/trial_request_screen.dart')
            .readAsStringSync();
    expect(form, contains('أوافق على شروط الاستخدام وسياسة الخصوصية'));
    expect(form, contains("ValueKey('trial-terms')"));
  });
}
