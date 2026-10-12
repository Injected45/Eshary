import 'package:eshary/core/theme.dart';
import 'package:eshary/features/profile/presentation/profile_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
              body: SingleChildScrollView(child: ChangePasswordSection())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _obscured(WidgetTester t, String key) =>
    t.widget<TextField>(find.byKey(ValueKey(key))).obscureText;

void main() {
  testWidgets(
      'the lock stays on the right, an eye is on the left of each field',
      (tester) async {
    await _open(tester);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    expect(find.byKey(const ValueKey('password-eye')), findsNWidgets(2));
    final lock = tester.getCenter(find.byIcon(Icons.lock_outline).first);
    final eye =
        tester.getCenter(find.byKey(const ValueKey('password-eye')).first);
    expect(lock.dx, greaterThan(eye.dx),
        reason: 'lock on the right, eye on the left');
  });

  testWidgets('hidden at first; the eye shows both, again hides both',
      (tester) async {
    await _open(tester);
    expect(_obscured(tester, 'new-password'), isTrue);
    expect(_obscured(tester, 'confirm-password'), isTrue);

    await tester.tap(find.byKey(const ValueKey('password-eye')).first);
    await tester.pump();
    expect(_obscured(tester, 'new-password'), isFalse);
    expect(_obscured(tester, 'confirm-password'), isFalse,
        reason: 'one eye shows both, to compare them');

    // the eye of the OTHER field works the same way
    await tester.tap(find.byKey(const ValueKey('password-eye')).last);
    await tester.pump();
    expect(_obscured(tester, 'new-password'), isTrue);
    expect(_obscured(tester, 'confirm-password'), isTrue);
  });

  testWidgets('shows, while typing, whether the two passwords match',
      (tester) async {
    await _open(tester);
    // nothing said until the second one is started
    expect(find.byKey(const ValueKey('passwords-match')), findsNothing);
    expect(find.byKey(const ValueKey('passwords-differ')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('new-password')), 'Abc12345!x');
    await tester.enterText(
        find.byKey(const ValueKey('confirm-password')), 'Abc1');
    await tester.pump();
    expect(find.byKey(const ValueKey('passwords-differ')), findsOneWidget);
    expect(find.text('غير متطابقتين'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('confirm-password')), 'Abc12345!x');
    await tester.pump();
    expect(find.byKey(const ValueKey('passwords-match')), findsOneWidget);
    expect(find.text('متطابقتان'), findsOneWidget);

    // the text typed is what was typed (no change by showing / hiding)
    await tester.tap(find.byKey(const ValueKey('password-eye')).first);
    await tester.pump();
    expect(find.text('Abc12345!x'), findsNWidgets(2));
  });
}
