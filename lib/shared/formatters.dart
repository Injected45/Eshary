import 'package:intl/intl.dart';

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
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  };
  return map[c] ?? c;
}

final DateFormat dateOnly = DateFormat('yyyy-MM-dd');
final DateFormat dateTime = DateFormat('yyyy-MM-dd HH:mm');
