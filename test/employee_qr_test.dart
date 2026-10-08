import 'package:eshary/features/employee_auth/domain/qr_payload.dart';
import 'package:eshary/features/sub_users/data/sub_users_repository.dart';
import 'package:eshary/features/sub_users/presentation/qr_display_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _token = 'a1' * 32; // 64 hex chars

void main() {
  group('employee QR payload', () {
    test('round trip', () {
      expect(employeeTokenFromQrPayload(employeeQrPayload(_token)), _token);
    });

    test('foreign QR refused', () {
      expect(employeeTokenFromQrPayload('https://example.com'), isNull);
      expect(employeeTokenFromQrPayload('WIFI:S:home;T:WPA;P:1234;;'), isNull);
      // A bare token is not ours: it must carry the prefix.
      expect(employeeTokenFromQrPayload(_token), isNull);
    });

    test('malformed token refused', () {
      expect(employeeTokenFromQrPayload('eshary://employee?t='), isNull);
      expect(employeeTokenFromQrPayload('eshary://employee?t=abc'), isNull);
      expect(
        employeeTokenFromQrPayload('eshary://employee?t=${'Z' * 64}'),
        isNull,
      );
    });

    test('surrounding whitespace is tolerated', () {
      expect(
        employeeTokenFromQrPayload('  ${employeeQrPayload(_token)}  '),
        _token,
      );
    });
  });

  group('QR dialog', () {
    SubUserQr qr() => SubUserQr(
          token: _token,
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        );

    testWidgets('what is drawn is what the scanner accepts', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrDisplayDialog(
              employeeName: 'أحمد',
              phoneNumber: '0912345678',
              qr: qr(),
            ),
          ),
        ),
      );
      final drawn = t.widget<QrDisplayDialog>(find.byType(QrDisplayDialog)).payload;
      expect(employeeTokenFromQrPayload(drawn), _token);
    });

    testWidgets('fits a 320dp phone without overflow', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: QrDisplayDialog(
                  employeeName: 'أحمد',
                  phoneNumber: '0912345678',
                  qr: qr(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
    });
  });
}
