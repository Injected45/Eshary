import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Saved clients and customers' companies added elsewhere (another phone, the
/// database) must reach an open app: by the refresh button and by itself.
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('the refresh button of both shells re-reads them', () {
    for (final f in [
      'lib/features/home/presentation/home_shell.dart',
      'lib/features/employee_auth/presentation/employee_home_shell.dart',
    ]) {
      final src = read(f);
      expect(src, contains('ref.invalidate(clientsListProvider)'), reason: f);
      expect(
        src,
        contains('ref.invalidate(exchangeCompaniesListProvider)'),
        reason: f,
      );
    }
  });

  test('the sync re-reads them every 30 seconds and stops with the shell', () {
    final src = read('lib/shared/realtime_sync.dart');
    expect(src, contains('Timer.periodic(const Duration(seconds: 30)'));
    expect(src, contains('ref.invalidate(clientsListProvider)'));
    expect(src, contains('listsTimer.cancel()'));
  });
}
