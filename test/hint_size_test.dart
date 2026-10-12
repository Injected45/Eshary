import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every hint in a field (exit / entry, sender / receiver, everywhere) has the
/// same size, set once in the theme: 11, two less than before.
void main() {
  test('the theme sets one hint size for the whole app', () {
    final hint = buildAppTheme().inputDecorationTheme.hintStyle;
    expect(hint, isNotNull);
    expect(hint!.fontSize, 10);
  });

  test('no screen overrides the hint style with its own size', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('theme.dart')) continue;
      if (f.readAsStringSync().contains('hintStyle:')) offenders.add(f.path);
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
