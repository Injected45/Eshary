import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/presentation/sign_in_screen.dart';
import 'package:eshary/features/auth/presentation/sign_up_screen.dart';
import 'package:eshary/features/cancellations/domain/cancellation.dart';
import 'package:eshary/features/cancellations/presentation/cancellations_providers.dart';
import 'package:eshary/features/cancellations/presentation/cancellations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OperationCancellation _cancellation(String id, String kind, double amount) =>
    OperationCancellation.fromJson({
      'id': id,
      'kind': kind,
      'operation_id': 'op-$id',
      'company_name': 'الرحالة',
      'exchange_name': 'بهار روز',
      'exchange_code': 'BR',
      'amount': amount,
      'reference': 'REF$id',
      'party_name': 'جهة $id',
      'operation_created_at': '2026-10-12T08:00:00Z',
      'operation_employee_name': 'المدير',
      'requested_by_name': null,
      'reason': 'سبب $id',
      'balance_before': 1000,
      'balance_after': 500,
      'cancelled_by_name': 'المدير',
      'cancelled_at': '2026-10-12T09:00:00Z',
    });

CancellationRequest _request(String id, String employee, double amount) =>
    CancellationRequest.fromJson({
      'id': id,
      'sub_user_id': 'u-$id',
      'employee_name': employee,
      'kind': 'transfer',
      'operation_id': 'op-$id',
      'amount': amount,
      'party_name': 'مستفيد $id',
      'reason': 'خطأ في المبلغ $id',
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'decided_at': null,
      'decision_note': null,
    });

Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cancellationsBetweenProvider.overrideWith(
          (ref, range) async => [
            _cancellation('1', 'transfer', 500),
            _cancellation('2', 'buy', 250),
          ],
        ),
        pendingCancelRequestsProvider.overrideWithValue([
          _request('r1', 'أحمد', 75),
        ]),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: CancellationsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tapHeader(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('closed: one title line per cancellation, no details',
      (tester) async {
    await _open(tester);
    // the title line of each cancellation, with its arrow
    expect(find.textContaining('خروج ملغى'), findsOneWidget);
    expect(find.textContaining('دخول ملغى'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancellation-header-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancellation-header-2')), findsOneWidget);
    // none of the details
    for (final detail in [
      'وقت الإلغاء',
      'الحساب',
      'ألغاها',
      'السبب',
      'الرصيد'
    ]) {
      expect(find.text(detail), findsNothing, reason: detail);
    }
    // a request is a title line too, with the buttons hidden until opened
    expect(find.byKey(const ValueKey('request-header-r1')), findsOneWidget);
    expect(find.textContaining('أحمد'), findsOneWidget);
    expect(find.text('موافقة وإلغاء'), findsNothing);
    expect(find.text('رفض'), findsNothing);
  });

  testWidgets(
      'opening one cancellation shows its details, opening another '
      'closes the first', (tester) async {
    await _open(tester);
    await tester.tap(_tapHeader('cancellation-header-1'));
    await tester.pumpAndSettle();
    expect(find.text('سبب 1'), findsOneWidget);
    expect(find.text('سبب 2'), findsNothing);

    await tester.tap(_tapHeader('cancellation-header-2'));
    await tester.pumpAndSettle();
    expect(find.text('سبب 2'), findsOneWidget);
    expect(find.text('سبب 1'), findsNothing, reason: 'the first one closed');

    // the same header again closes it: nothing open
    await tester.tap(_tapHeader('cancellation-header-2'));
    await tester.pumpAndSettle();
    expect(find.text('سبب 2'), findsNothing);
  });

  testWidgets('one open card across requests and cancellations',
      (tester) async {
    await _open(tester);
    await tester.tap(_tapHeader('request-header-r1'));
    await tester.pumpAndSettle();
    expect(find.text('موافقة وإلغاء'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);

    await tester.tap(_tapHeader('cancellation-header-1'));
    await tester.pumpAndSettle();
    expect(find.text('سبب 1'), findsOneWidget);
    expect(find.text('موافقة وإلغاء'), findsNothing,
        reason: 'the request closed when a cancellation opened');
  });

  test('every cancellation is yellow, in one place', () {
    const c = AppColors.cancelled;
    // golden yellow leaning to orange: strong red, a bit less green, no blue
    expect(c.r * 255, greaterThan(200));
    expect(c.g * 255, greaterThan(150));
    expect(c.b * 255, lessThan(60));
    expect(c.g / c.r, inInclusiveRange(0.6, 0.85),
        reason: 'not neon yellow, not orange');
    // and none of the cancellation screens carries a colour of its own
    for (final f in [
      'lib/features/cancellations/presentation/cancellations_screen.dart',
      'lib/features/cancellations/presentation/operation_cancel_bar.dart',
      'lib/features/cancellations/presentation/cancel_operation_dialog.dart',
      'lib/features/companies/presentation/account_statement_screen.dart',
      'lib/features/transfers/presentation/transfers_screen.dart',
      'lib/features/currency_buy/presentation/currency_buy_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('Colors.purple'), isFalse, reason: f);
      expect(src, contains('AppColors.cancelled'), reason: f);
    }
  });

  group('the eye on the sign-in screens', () {
    Future<void> openScreen(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: screen,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool hidden(WidgetTester tester) => tester
        .widget<EditableText>(find.descendant(
          of: find.widgetWithText(TextField, 'كلمة المرور'),
          matching: find.byType(EditableText),
        ))
        .obscureText;

    for (final entry in {
      'sign in': const SignInScreen(),
      'sign up': const SignUpScreen(),
    }.entries) {
      testWidgets('${entry.key}: hidden at first, the eye shows the characters',
          (tester) async {
        await openScreen(tester, entry.value);
        await tester.enterText(
          find.widgetWithText(TextField, 'كلمة المرور'),
          'Abc12345',
        );
        expect(hidden(tester), isTrue);

        await tester.tap(find.byKey(const ValueKey('password-eye')));
        await tester.pumpAndSettle();
        expect(hidden(tester), isFalse);

        await tester.tap(find.byKey(const ValueKey('password-eye')));
        await tester.pumpAndSettle();
        expect(hidden(tester), isTrue);
      });

      testWidgets('${entry.key}: the eye is on the left of the field',
          (tester) async {
        await openScreen(tester, entry.value);
        final field =
            tester.getRect(find.widgetWithText(TextField, 'كلمة المرور'));
        final eye =
            tester.getCenter(find.byKey(const ValueKey('password-eye')));
        final lock = tester.getCenter(find.byIcon(Icons.lock_outline));
        expect(eye.dx, lessThan(field.center.dx), reason: 'left half');
        expect(lock.dx, greaterThan(field.center.dx),
            reason: 'lock stays right');
      });
    }
  });
}
