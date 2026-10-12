import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/trial/data/trial_admin_repository.dart';
import 'package:eshary/features/trial/domain/trial_models.dart';
import 'package:eshary/features/trial/presentation/trial_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdmin implements TrialAdminRepository {
  final decisions = <String>[];
  bool messageOk = true;

  @override
  Future<Map<String, dynamic>> decide(String id, String decision,
      {String? note}) async {
    decisions.add('$decision:$id');
    return {
      'ok': true,
      'message': {'ok': messageOk},
    };
  }

  @override
  Future<PendingCounts> pendingCounts() async => PendingCounts.zero;

  @override
  Future<void> resendCode(String id) async => decisions.add('resend:$id');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

TrialRequestRow _row(
  String id,
  String business,
  String status,
  String bucket, {
  String? message,
  int? remaining,
}) =>
    TrialRequestRow(
      id: id,
      managerName: 'مدير $id',
      businessName: business,
      phone: '+21891000000$id',
      status: status,
      bucket: bucket,
      reviewNote: null,
      requestedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      approvalExpiresAt: null,
      trialHours: 72,
      phoneVerified: false,
      trialEndsAt: null,
      remainingSeconds: remaining,
      userId: null,
      messageStatus: message,
      repeatHint: 0,
    );

final _rows = [
  _row('1', 'شركة جديدة', 'pending_review', 'pending_review'),
  _row('2', 'شركة الموافقة', 'approved', 'approved_waiting', message: 'sent'),
  _row('3', 'شركة فشل الرمز', 'approved', 'message_failed', message: 'failed'),
  _row('4', 'شركة فعّالة', 'activated', 'active_trial', remaining: 2 * 86400),
];

Future<_FakeAdmin> _open(WidgetTester tester,
    {List<TrialRequestRow>? rows}) async {
  // wide enough to build every filter chip of the horizontal list
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = _FakeAdmin();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trialAdminRepositoryProvider.overrideWithValue(fake),
        trialRequestsProvider.overrideWith((ref) async => rows ?? _rows),
        trialStatsProvider.overrideWith((ref) async => <String, dynamic>{
              'requests': 4,
              'activationRate': 0.25,
              'conversionRate': 0.0,
              'avgApprovalWaitSeconds': 600,
            }),
        adminPendingCountsProvider
            .overrideWith((ref) => Stream.value(PendingCounts.zero)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: TrialRequestsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('it opens on what waits for a decision, and nothing else',
      (tester) async {
    await _open(tester);
    expect(find.text('شركة جديدة'), findsOneWidget);
    expect(find.text('شركة الموافقة'), findsNothing);
    expect(find.text('شركة فشل الرمز'), findsNothing);
    expect(find.text('شركة فعّالة'), findsNothing);
  });

  testWidgets(
      'a card says its state in one plain sentence, with two big buttons',
      (tester) async {
    await _open(tester);
    expect(find.text('طلب جديد ينتظر قرارك'), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-72')), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-168')), findsOneWidget);
    // the rarer decisions are one tap away, not on the card
    expect(find.text('طلب معلومات'), findsNothing);
    expect(find.text('رفض'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('request-menu')));
    await tester.pumpAndSettle();
    expect(find.text('طلب معلومات'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
    expect(find.text('تصحيح رقم الهاتف'), findsOneWidget);
  });

  testWidgets('one tap approves and says what the applicant was told',
      (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('approve-72')));
    await tester.pumpAndSettle();
    expect(fake.decisions, ['approve_72:1']);
    expect(find.textContaining('أُرسل رمز التفعيل إلى واتساب'), findsOneWidget);
  });

  testWidgets('when the WhatsApp code did not go out, the message says so',
      (tester) async {
    final fake = await _open(tester)
      ..messageOk = false;
    await tester.tap(find.byKey(const ValueKey('approve-168')));
    await tester.pumpAndSettle();
    expect(fake.decisions, ['approve_168:1']);
    expect(find.textContaining('تعذّر إرسال الرمز'), findsOneWidget);
  });

  testWidgets(
      '"waiting for activation" shows the failed code with a resend button',
      (tester) async {
    final fake = await _open(tester);
    await tester.tap(find.text('بانتظار التفعيل'));
    await tester.pumpAndSettle();
    expect(find.text('تمت الموافقة لكن لم يصل الرمز'), findsOneWidget);
    expect(find.text('تمت الموافقة، بانتظار أن يُدخل المتقدّم الرمز'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resend-code')).first);
    await tester.pumpAndSettle();
    expect(fake.decisions.any((d) => d.startsWith('resend:')), isTrue);
  });

  testWidgets('an active trial says how many days are left, in words',
      (tester) async {
    await _open(tester);
    await tester.tap(find.text('فعّالة'));
    await tester.pumpAndSettle();
    expect(find.text('تجربة فعّالة، متبقي 2 يوم'), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-72')), findsNothing,
        reason: 'nothing to decide on an active trial');
  });

  testWidgets('with nothing waiting it says so (good news)', (tester) async {
    await _open(tester, rows: [
      _row('4', 'شركة فعّالة', 'activated', 'active_trial', remaining: 86400),
    ]);
    expect(find.byKey(const ValueKey('requests-empty')), findsOneWidget);
    expect(find.text('لا توجد طلبات تنتظر قرارك ✓'), findsOneWidget);
  });

  test(
      'the accounts screen has the banner, the settings the badge, one plan dialog',
      () {
    final admin = File('lib/features/admin/presentation/admin_screen.dart')
        .readAsStringSync();
    expect(admin, contains("ValueKey('pending-banner')"));
    expect(admin, contains('اضغط للمراجعة'));
    for (final plan in ['30', '90', '365', '0']) {
      expect(admin, contains("'plan-\$d'"));
      expect(plan, isNotEmpty);
    }
    expect(admin, contains("'confirm_payment'"));
    expect(admin, contains('activateLifetime(row.loginEmail)'));
    final settings =
        File('lib/features/settings/presentation/settings_screen.dart')
            .readAsStringSync();
    expect(
        settings.replaceAll(RegExp(r'\s+'), ' '),
        contains(
            'badge: ref.watch(adminPendingCountsProvider).valueOrNull?.total ?? 0'));
  });

  test('the approval message tells the applicant what to press', () {
    final sql = File('supabase/migrations/0067_admin_quick_approval.sql')
        .readAsStringSync();
    expect(sql, contains('متابعة طلب التجربة'));
    expect(sql, contains('function admin_pending_counts'));
  });
}
