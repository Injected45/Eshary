import 'package:eshary/core/theme.dart';
import 'package:eshary/features/license/domain/license_status.dart';
import 'package:eshary/features/trial/data/trial_repository.dart';
import 'package:eshary/features/trial/domain/trial_models.dart';
import 'package:eshary/features/trial/presentation/subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SubscriptionState _state(
  String status, {
  int? remaining,
  List<String> actions = const ['read', 'write', 'export'],
}) =>
    SubscriptionState(
      status: status,
      serverNow: DateTime.utc(2026, 10, 10, 12),
      trialEndsAt: remaining == null
          ? DateTime.utc(2026, 10, 9, 12)
          : DateTime.utc(2026, 10, 10, 12).add(Duration(seconds: remaining)),
      remainingSeconds: remaining,
      allowedActions: actions,
      receivedAtTicks: kMonotonic.elapsedMilliseconds,
    );

Future<void> _show(WidgetTester tester, SubscriptionState s) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionStateProvider.overrideWith((ref) async => s),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: SubscriptionScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the countdown follows monotonic time, not the date', () {
    final s = _state('trial', remaining: 3600);
    final left = remainingOf(s)!;
    expect(left.inMinutes, inInclusiveRange(59, 60));
    expect(remainingOf(_state('trial', remaining: 0)), Duration.zero);
    expect(formatRemaining(const Duration(days: 2, hours: 5)), '2 يوم و5 ساعة');
    expect(formatRemaining(const Duration(minutes: 30)), '30 دقيقة');
    expect(formatRemaining(const Duration(seconds: 20)), 'أقل من دقيقة');
  });

  test('times are shown in Libya time (UTC+2)', () {
    expect(formatTripoli(DateTime.utc(2026, 10, 10, 22, 30)), '2026-10-11 00:30');
  });

  test('an expired subscriber may still enter, read only', () {
    LicenseStatus s(String status, {bool valid = false, bool admin = false}) =>
        LicenseStatus(
          status: status,
          licenseType: null,
          trialEndsAt: null,
          isValid: valid,
          isAdmin: admin,
        );
    expect(s('trial').isReadOnly, isTrue);
    expect(s('expired').isReadOnly, isTrue);
    expect(s('active').isReadOnly, isTrue);
    expect(s('trial', valid: true).isReadOnly, isFalse);
    expect(s('blocked').isReadOnly, isFalse);
    expect(s('pending').isReadOnly, isFalse);
  });

  testWidgets('trial: shows the time left and the requests', (tester) async {
    await _show(tester, _state('trial', remaining: 7200));
    expect(find.text('فترة تجريبية'), findsOneWidget);
    expect(find.text('قراءة وكتابة وتصدير'), findsOneWidget);
    expect(find.byKey(const ValueKey('request-subscribe')), findsOneWidget);
  });

  testWidgets('expired: read and export only, data kept', (tester) async {
    await _show(
      tester,
      _state('expired', actions: const ['read', 'export']),
    );
    expect(find.text('انتهى الاشتراك'), findsOneWidget);
    expect(find.text('قراءة وتصدير فقط'), findsOneWidget);
    expect(find.textContaining('بياناتك محفوظة'), findsOneWidget);
    expect(find.byKey(const ValueKey('request-extend')), findsOneWidget);
  });

  testWidgets('suspended: no requests, only the notice', (tester) async {
    await _show(tester, _state('suspended', actions: const []));
    expect(find.text('موقوف'), findsOneWidget);
    expect(find.byKey(const ValueKey('request-subscribe')), findsNothing);
  });
}
