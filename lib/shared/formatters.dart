import 'package:intl/intl.dart';
import './libya_time.dart';

/// Money formatter with both Latin and Arabic-Indic digit options.
/// Source HTML used Latin digits (`Intl.NumberFormat('en-US', ...)`) so
/// `formatMoney` keeps that as the default for screen parity.
/// `formatMoneyArabic` is available for displays that prefer Arabic-Indic.

final NumberFormat _moneyLatin =
    NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: 2);

final NumberFormat _moneyArabic =
    NumberFormat.decimalPatternDigits(locale: 'ar', decimalDigits: 2);

String formatMoney(num value) => _moneyLatin.format(value);

String formatMoneyArabic(num value) => _moneyArabic.format(value);

/// Dinars for [usd] dollars at [rate], exactly as the database computes them
/// (migration 0081): the rate to 4 decimals, the result rounded half up to the
/// dirham. Integer arithmetic, so no binary-fraction error. Only a preview: the
/// stored figure always comes from the database.
double lydFor(double usd, double rate) {
  final cents = _scaledHalfUp(usd, 2);
  final units = _scaledHalfUp(rate, 4);
  final product = cents * units; // in 1/1,000,000 dinar
  final rounded = (product.abs() + BigInt.from(5000)) ~/ BigInt.from(10000);
  return (product.isNegative ? -rounded : rounded).toInt() / 100;
}

/// [value] in units of 10^-[places], rounded half up from its DECIMAL digits
/// (7.12345 is 7.1234499… as a double; the database, which rounds the decimal
/// 7.12345, gets 7.1235, and so does this).
BigInt _scaledHalfUp(double value, int places) {
  final digits = value.abs().toStringAsFixed(places + 4).replaceAll('.', '');
  final n = (BigInt.parse(digits) + BigInt.from(5000)) ~/ BigInt.from(10000);
  return value.isNegative ? -n : n;
}

/// A rate as the database keeps it (4 decimals), without useless trailing
/// zeros: 7.25, 7.1235, 7.
String formatRate(num value) {
  final units = _scaledHalfUp(value.toDouble(), 4);
  final whole = units.abs() ~/ BigInt.from(10000);
  final frac = (units.abs() % BigInt.from(10000))
      .toString()
      .padLeft(4, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final sign = units.isNegative ? '-' : '';
  return frac.isEmpty ? '$sign$whole' : '$sign$whole.$frac';
}

/// A typed exchange rate. Unlike an amount, a rate has no thousands: a comma
/// (or the Arabic decimal mark) is the decimal point, so "7,25" is 7.25 —
/// never 725, which [parseMoney] would make of it.
double parseRate(String input) {
  final s = input
      .trim()
      .replaceAll('،', '.')
      .replaceAll('٫', '.')
      .replaceAll(',', '.');
  final latin = s.split('').map(_arabicDigitToLatin).join();
  // more than one point: not a number
  if ('.'.allMatches(latin).length > 1) return 0;
  return double.tryParse(latin) ?? 0;
}

/// The range the database accepts for a rate (migration 0084): above 1 and at
/// most 100 dinars per dollar.
bool rateInRange(double rate) => rate > 1 && rate <= 100;

double parseMoney(String input) {
  if (input.isEmpty) return 0;
  // Strip thousands separators and convert Arabic-Indic digits if present.
  final normalized = input
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll('٫', '.')
      .split('')
      .map(_arabicDigitToLatin)
      .join()
      .trim();
  return double.tryParse(normalized) ?? 0;
}

String _arabicDigitToLatin(String c) {
  const map = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };
  return map[c] ?? c;
}

final DateFormat dateOnly = LibyaDateFormat('yyyy-MM-dd');
final DateFormat dateTime = LibyaDateFormat('yyyy-MM-dd HH:mm');
