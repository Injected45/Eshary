import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/data/auth_repository.dart';
import 'package:eshary/features/auth/data/member_auth_repository.dart'
    show MemberRefused;
import 'package:eshary/features/auth/data/phone_link_repository.dart';
import 'package:eshary/features/auth/presentation/link_phone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Link implements PhoneLinkRepository {
  final sent = <String>[];
  final confirmed = <String>[];
  Object? confirmError;

  @override
  Future<String> requestCode(String phone) async {
    sent.add(phone);
    return '09*****678';
  }

  @override
  Future<void> confirm(String phone, String otp) async {
    if (confirmError != null) throw confirmError!;
    confirmed.add('$phone:$otp');
  }

  @override
  Future<bool> needsPhone() async => true;
}

class _Auth implements AuthRepository {
  bool signedOut = false;

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Session _session(String email) => Session(
      accessToken: 't',
      tokenType: 'bearer',
      user: User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        email: email,
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(textDirection: TextDirection.rtl, child: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('link phone: the last step', () {
    Future<_Link> open(WidgetTester tester) async {
      final link = _Link();
      await pumpScreen(
        tester,
        const LinkPhoneScreen(),
        overrides: [
          phoneLinkRepositoryProvider.overrideWithValue(link),
          currentSessionProvider.overrideWithValue(_session('rahala@gmail.com')),
          authRepositoryProvider.overrideWithValue(_Auth()),
        ],
      );
      return link;
    }

    testWidgets('shows the Google account that was chosen', (tester) async {
      await open(tester);
      expect(find.text('rahala@gmail.com'), findsOneWidget);
      expect(find.text('رقم الهاتف (واتساب)'), findsOneWidget);
      // only the phone is asked: no e-mail field at all
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a bad number is refused before anything is sent',
        (tester) async {
      final link = await open(tester);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('إرسال رمز التحقق'));
      await tester.pumpAndSettle();
      expect(link.sent, isEmpty);
      expect(find.textContaining('09XXXXXXXX'), findsWidgets);
    });

    testWidgets('phone, one WhatsApp code, confirmed by itself',
        (tester) async {
      final link = await open(tester);
      await tester.enterText(find.byType(TextField), '0912345678');
      await tester.tap(find.text('إرسال رمز التحقق'));
      await tester.pumpAndSettle();
      expect(link.sent, ['0912345678']);
      expect(find.text('رمز واتساب'), findsOneWidget);
      expect(find.text('رمز البريد الإلكتروني'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '4821');
      await tester.pumpAndSettle();
      expect(link.confirmed, ['0912345678:4821']);
    });

    testWidgets('a wrong code says how many tries are left', (tester) async {
      final link = await open(tester)
        ..confirmError = const MemberRefused('invalid_otp', left: 2);
      await tester.enterText(find.byType(TextField), '0912345678');
      await tester.tap(find.text('إرسال رمز التحقق'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1111');
      await tester.pumpAndSettle();
      expect(link.confirmed, isEmpty);
      expect(find.textContaining('متبقي 2 محاولة'), findsOneWidget);
    });

    testWidgets('"استخدام حساب آخر" signs out', (tester) async {
      final auth = _Auth();
      await pumpScreen(
        tester,
        const LinkPhoneScreen(),
        overrides: [
          phoneLinkRepositoryProvider.overrideWithValue(_Link()),
          currentSessionProvider.overrideWithValue(_session('a@b.ly')),
          authRepositoryProvider.overrideWithValue(auth),
        ],
      );
      await tester.tap(find.text('استخدام حساب آخر'));
      await tester.pumpAndSettle();
      expect(auth.signedOut, isTrue);
    });
  });

}
