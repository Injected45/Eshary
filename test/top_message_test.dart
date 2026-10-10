import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/shared/top_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> open(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('a message appears at the TOP, under the status bar',
      (tester) async {
    final ctx = await open(tester);
    showTopSnackBar(ctx, const SnackBar(content: Text('تم الحفظ')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.getRect(find.byKey(const ValueKey('top-message')));
    expect(box.top, greaterThanOrEqualTo(44), reason: 'below the status bar');
    expect(box.top, lessThan(80));
    expect(box.bottom, lessThan(400), reason: 'in the upper half, not the bottom');
    expect(find.text('تم الحفظ'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'no bottom snackbar');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('تم الحفظ'), findsNothing, reason: 'it goes away by itself');
  });

  testWidgets('a new message replaces the one on screen', (tester) async {
    final ctx = await open(tester);
    showTopSnackBar(ctx, const SnackBar(content: Text('الأولى')));
    await tester.pump(const Duration(milliseconds: 100));
    showTopSnackBar(ctx, const SnackBar(content: Text('الثانية')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('الأولى'), findsNothing);
    expect(find.text('الثانية'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an error keeps its colour; a tap closes it', (tester) async {
    final ctx = await open(tester);
    showTopSnackBar(
      ctx,
      SnackBar(
        backgroundColor: AppColors.negative,
        content: const Text('خطأ'),
        duration: const Duration(seconds: 30),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.widget<Container>(find.byKey(const ValueKey('top-message')));
    final fill = (box.decoration! as BoxDecoration).color!;
    expect(fill.r, greaterThan(fill.b), reason: 'an error keeps a red tint');
    await tester.tap(find.text('خطأ'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('خطأ'), findsNothing);
  });

  testWidgets('the normal message is translucent white glass, not a flat white',
      (tester) async {
    final ctx = await open(tester);
    showTopSnackBar(ctx, const SnackBar(content: Text('تم')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.widget<Container>(find.byKey(const ValueKey('top-message')));
    final fill = (box.decoration! as BoxDecoration).color!;
    expect(fill.a, lessThan(1), reason: 'translucent');
    expect(fill.r, lessThan(0.75), reason: 'never a flat bright white');
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('no screen shows a bottom snackbar any more', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('top_message.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('.showSnackBar(') || src.contains('hideCurrentSnackBar')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
