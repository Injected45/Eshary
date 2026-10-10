import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/data/member_auth_repository.dart';
import 'package:eshary/features/auth/presentation/phone_login_screen.dart';
import 'package:eshary/features/members/data/member_invites_repository.dart';
import 'package:eshary/features/members/domain/member_invite.dart';
import 'package:eshary/features/members/presentation/invite_qr_dialog.dart';
import 'package:eshary/features/members/presentation/invite_redeem_screen.dart';
import 'package:eshary/features/members/presentation/member_invites_screen.dart';
import 'package:eshary/shared/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

final _token = 'ab12' * 16; // 64 hex characters

class _Auth implements MemberAuthRepository {
  final calls = <String>[];
  Object? previewError;
  Object? requestError;

  @override
  Future<InvitePreview> invitePreview(String token) async {
    calls.add('preview:$token');
    if (previewError != null) throw previewError!;
    return const InvitePreview(name: 'رافع المهدي', phoneMasked: '09*****678');
  }

  @override
  Future<String> inviteRequestOtp(String token, String phone) async {
    calls.add('request:$phone');
    if (requestError != null) throw requestError!;
    return '09*****678';
  }

  @override
  Future<void> redeemInvite(String token, String phone, String otp) async {
    calls.add('redeem:$token:$phone:$otp');
  }

  @override
  Future<String> phoneLoginRequest(String phone) async {
    calls.add('login-request:$phone');
    return '09*****678';
  }

  @override
  Future<void> phoneLogin(String phone, String otp) async {
    calls.add('login:$phone:$otp');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Invites implements MemberInvitesRepository {
  final created = <String>[];
  final revoked = <String>[];
  List<MemberInvite> rows = [];

  @override
  Future<CreatedInvite> create({
    required String name,
    required String phone,
    required InviteLicense license,
    int hours = 24,
  }) async {
    created.add('$name|$phone|${license.db}|$hours');
    return CreatedInvite(
      id: 'i1',
      token: _token,
      expiresAt: DateTime.now().add(Duration(hours: hours)),
    );
  }

  @override
  Future<List<MemberInvite>> list() async => rows;

  @override
  Future<void> revoke(String id) async => revoked.add(id);
}

MemberInvite _invite(String id, String status, {String license = 'trial'}) =>
    MemberInvite.fromJson({
      'id': id,
      'label': 'مشترك $id',
      'phone': '0912345678',
      'license': license,
      'status': status,
      'created_at': '2026-10-10T08:00:00Z',
      'expires_at': '2026-10-11T08:00:00Z',
      'used_at': status == 'used' ? '2026-10-10T09:00:00Z' : null,
    });

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: home),
      ),
    );

void main() {
  group('the invitation text', () {
    test('payload round trip', () {
      expect(invitePayload(_token), 'eshary://invite?t=$_token');
      expect(inviteTokenFromText(invitePayload(_token)), _token);
    });

    test('the bare secret and the whole WhatsApp message are read', () {
      expect(inviteTokenFromText(_token), _token);
      expect(inviteTokenFromText('  $_token \n'), _token);
      final msg = inviteShareText(
        name: 'سامي',
        license: InviteLicense.lifetime,
        expiresAt: DateTime(2026, 10, 11, 8),
        payload: invitePayload(_token),
      );
      expect(inviteTokenFromText(msg), _token);
      expect(msg, contains('سامي'));
      expect(msg, contains('دائم'));
    });

    test('anything else is not an invitation', () {
      for (final raw in [
        '',
        'hello',
        '12345',
        'eshary://employee?t=$_token',
        'eshary://invite?t=short',
        'https://example.com/$_token/x',
        'ab12' * 15,
      ]) {
        expect(inviteTokenFromText(raw), isNull, reason: raw);
      }
    });

    test('the model reads the server rows', () {
      final i = _invite('a', 'expired', license: 'lifetime');
      expect(i.status, InviteStatus.expired);
      expect(i.license, InviteLicense.lifetime);
      expect(i.license.label, 'دائم');
      expect(InviteLicense.parse('trial').label, 'تجريبي 3 أيام');
      // the administrator role is not an option of an invitation
      expect(
        InviteLicense.values.map((l) => l.name),
        unorderedEquals(['trial', 'lifetime', 'pending']),
      );
    });
  });

  group('administrator: the invitations screen', () {
    Future<_Invites> open(WidgetTester tester, List<MemberInvite> rows) async {
      final repo = _Invites()..rows = rows;
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          const MemberInvitesScreen(),
          [memberInvitesRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('lists the invitations with their state', (tester) async {
      await open(tester, [
        _invite('1', 'pending'),
        _invite('2', 'used'),
        _invite('3', 'revoked'),
        _invite('4', 'expired'),
      ]);
      expect(find.text('بانتظار الدخول'), findsOneWidget);
      expect(find.text('تم الدخول'), findsOneWidget);
      expect(find.text('مُلغاة'), findsOneWidget);
      expect(find.text('منتهية'), findsOneWidget);
      // only an open invitation can be revoked
      expect(find.text('إلغاء الدعوة'), findsOneWidget);
    });

    testWidgets('empty list explains itself', (tester) async {
      await open(tester, const []);
      expect(find.textContaining('لا توجد دعوات بعد'), findsOneWidget);
    });

    testWidgets('create: name + phone + licence, then the QR appears',
        (tester) async {
      final repo = await open(tester, const []);
      await tester.tap(find.byKey(const ValueKey('new-invite')));
      await tester.pumpAndSettle();
      // a bad phone is refused on the spot
      await tester.enterText(find.byKey(const ValueKey('invite-name')), 'رافع');
      await tester.enterText(find.byKey(const ValueKey('invite-phone')), '123');
      await tester.tap(find.byKey(const ValueKey('invite-create')));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(find.textContaining('09XXXXXXXX'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('invite-phone')),
        '0912345678',
      );
      await tester.tap(find.byKey(const ValueKey('invite-license-lifetime')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('invite-create')));
      await tester.pumpAndSettle();
      expect(repo.created, ['رافع|0912345678|lifetime|24']);

      // the QR dialog: the QR holds exactly the payload, all three ways to send
      expect(find.byKey(const ValueKey('invite-qr')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final dialog = tester.widget<InviteQrDialog>(find.byType(InviteQrDialog));
      expect(dialog.invite.payload, invitePayload(_token));
      expect(find.byKey(const ValueKey('invite-share-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-share-text')), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-copy')), findsOneWidget);
      expect(find.textContaining('الصلاحية: دائم'), findsOneWidget);
      expect(find.textContaining('لمرة واحدة'), findsWidgets);
    });

    testWidgets('revoke asks first, then revokes', (tester) async {
      final repo = await open(tester, [_invite('9', 'pending')]);
      await tester.tap(find.text('إلغاء الدعوة'));
      await tester.pumpAndSettle();
      expect(repo.revoked, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'إلغاء الدعوة'));
      await tester.pumpAndSettle();
      expect(repo.revoked, ['9']);
    });
  });

  group('subscriber: لدي دعوة', () {
    Future<_Auth> open(WidgetTester tester, {_Auth? auth}) async {
      final a = auth ?? _Auth();
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          const InviteRedeemScreen(),
          [memberAuthRepositoryProvider.overrideWithValue(a)],
        ),
      );
      await tester.pumpAndSettle();
      return a;
    }

    testWidgets('paste the message, type the phone, enter the code',
        (tester) async {
      final auth = await open(tester);
      expect(find.byKey(const ValueKey('scan-invite')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('paste-field')),
        'دعوة لك\n${invitePayload(_token)}\nشكراً',
      );
      await tester.tap(find.byKey(const ValueKey('continue-invite')));
      await tester.pumpAndSettle();
      expect(auth.calls, ['preview:$_token']);
      expect(find.textContaining('مرحباً رافع المهدي'), findsOneWidget);
      expect(find.textContaining('09*****678'), findsOneWidget);
      // the phone is asked, not shown: the QR alone is not enough
      expect(find.byKey(const ValueKey('phone-field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('phone-field')),
        '0912345678',
      );
      await tester.tap(find.byKey(const ValueKey('send-code')));
      await tester.pumpAndSettle();
      expect(auth.calls.last, 'request:0912345678');

      await tester.enterText(find.byKey(const ValueKey('code-field')), '4821');
      await tester.pumpAndSettle();
      expect(auth.calls.last, 'redeem:$_token:0912345678:4821');
    });

    testWidgets('text that is not an invitation is refused', (tester) async {
      final auth = await open(tester);
      await tester.enterText(find.byKey(const ValueKey('paste-field')), 'مرحبا');
      await tester.tap(find.byKey(const ValueKey('continue-invite')));
      await tester.pumpAndSettle();
      expect(auth.calls, isEmpty);
      expect(find.textContaining('لم أجد رمز دعوة'), findsOneWidget);
    });

    testWidgets('a used / expired invitation says so in Arabic',
        (tester) async {
      final auth = _Auth()..previewError = const MemberRefused('invite_invalid');
      await open(tester, auth: auth);
      await tester.enterText(find.byKey(const ValueKey('paste-field')), _token);
      await tester.tap(find.byKey(const ValueKey('continue-invite')));
      await tester.pumpAndSettle();
      expect(find.textContaining('استُخدمت أو انتهت أو أُلغيت'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-field')), findsNothing);
    });

    testWidgets('a wrong phone shows the tries left', (tester) async {
      final auth = _Auth()
        ..requestError = const MemberRefused('phone_mismatch', left: 3);
      await open(tester, auth: auth);
      await tester.enterText(find.byKey(const ValueKey('paste-field')), _token);
      await tester.tap(find.byKey(const ValueKey('continue-invite')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('phone-field')),
        '0999999999',
      );
      await tester.tap(find.byKey(const ValueKey('send-code')));
      await tester.pumpAndSettle();
      expect(find.textContaining('غير مطابق للرقم المسجّل'), findsOneWidget);
      expect(find.textContaining('متبقي 3 محاولة'), findsOneWidget);
    });
  });

  testWidgets('sign-in by phone number: phone then code', (tester) async {
    final auth = _Auth();
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const PhoneLoginScreen(),
        [memberAuthRepositoryProvider.overrideWithValue(auth)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-field')),
      '0912345678',
    );
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('code-field')), '1234');
    await tester.pumpAndSettle();
    expect(auth.calls, ['login-request:0912345678', 'login:0912345678:1234']);
  });

  group('messages and wiring', () {
    test('the refusals read in Arabic', () {
      for (final code in [
        'invite_invalid',
        'phone_mismatch',
        'phone_not_found',
        'invite_not_found',
      ]) {
        final msg = friendlyError(MemberRefused(code));
        expect(msg, isNot(contains(code)), reason: code);
        expect(RegExp('[؀-ۿ]').hasMatch(msg), isTrue);
      }
    });

    test('routes, buttons and the administrator entry exist', () {
      final router = File('lib/core/router.dart').readAsStringSync();
      expect(router, contains("path: '/invite'"));
      expect(router, contains("path: '/phone-login'"));
      expect(router, contains("loc == '/invite'"));
      final admin = File('lib/features/admin/presentation/admin_screen.dart')
          .readAsStringSync();
      expect(admin, contains("ValueKey('member-invites')"));
      expect(admin, contains('MemberInvitesScreen()'));
    });

    test('the Edge Function handles the invitation and phone entrances', () {
      final fn = File('supabase/functions/member-session/index.ts')
          .readAsStringSync();
      expect(fn, contains('action === "invite"'));
      expect(fn, contains('action === "phone"'));
      expect(fn, contains('member_invite_consume'));
      expect(fn, contains('member_invite_finish'));
      expect(fn, contains('member_email_for_phone'));
      // the code is checked in the database before the account is made
      expect(fn.indexOf('p_commit: false'), lessThan(fn.indexOf('createUser')));
    });

    test('the migration never grants the administrator role', () {
      final sql = File('supabase/migrations/0058_member_invites.sql')
          .readAsStringSync();
      expect(sql, contains("license in ('trial', 'lifetime', 'pending')"));
      expect(sql, isNot(contains('is_admin = true')));
      expect(
        sql,
        contains(
          'grant execute on function member_invite_consume(text, text, text, boolean) to service_role',
        ),
      );
    });
  });
}
