import 'package:eshary/shared/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('formats two decimals with thousands separator', () {
      expect(formatMoney(1234.5), '1,234.50');
      expect(formatMoney(0), '0.00');
      expect(formatMoney(1000000), '1,000,000.00');
    });
  });

  group('parseMoney', () {
    test('handles plain numbers', () {
      expect(parseMoney('1234.50'), 1234.50);
    });

    test('strips comma thousands separator', () {
      expect(parseMoney('1,234.50'), 1234.50);
    });

    test('returns 0 on empty string', () {
      expect(parseMoney(''), 0);
    });

    test('converts Arabic-Indic digits', () {
      expect(parseMoney('١٢٣٤'), 1234);
      expect(parseMoney('١٬٢٣٤٫٥٠'), 1234.50);
    });

    test('returns 0 on garbage', () {
      expect(parseMoney('not a number'), 0);
    });
  });
}
