import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // OLED-friendly base.
  static const bgDeep = Color(0xFF020617);   // slate-950
  static const bgPanel = Color(0xFF0B1220);  // slightly lighter for stacking

  // Glass overlay tones.
  static const glassFill = Color(0x14FFFFFF);   // 8% white
  static const glassFillStrong = Color(0x1FFFFFFF); // 12%
  static const glassBorder = Color(0x1FFFFFFF);  // 12% white
  static const glassBorderStrong = Color(0x33FFFFFF); // 20%

  // Accents.
  static const accent = Color(0xFF22D3EE);   // cyan-400, primary brand glow
  static const accentDim = Color(0xFF0E7490); // cyan-700
  static const positive = Color(0xFF22C55E); // green-500 — currency buy / income
  static const negative = Color(0xFFEF4444); // red-500 — transfers / outflow
  static const warning = Color(0xFFF59E0B);  // amber-500 — pending

  // Text.
  static const textHigh = Color(0xFFF8FAFC);   // slate-50
  static const textMid = Color(0xFFCBD5E1);    // slate-300
  static const textLow = Color(0xFF94A3B8);    // slate-400
  static const textDim = Color(0xFF64748B);    // slate-500
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
    surface: AppColors.bgDeep,
    primary: AppColors.accent,
    secondary: AppColors.positive,
    error: AppColors.negative,
    onSurface: AppColors.textHigh,
    onPrimary: Colors.black,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Almarai',
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AppColors.bgPanel,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: const TextStyle(
        fontFamily: 'Almarai',
        fontSize: 13,
        color: AppColors.textHigh,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textHigh,
      titleTextStyle: TextStyle(
        fontFamily: 'Almarai',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textHigh,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.glassFill,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.glassFill,
      isDense: true,
      labelStyle: const TextStyle(color: AppColors.textLow, fontSize: 13),
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Almarai',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textHigh,
        side: const BorderSide(color: AppColors.glassBorderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Almarai',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(
          fontFamily: 'Almarai',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.glassBorder,
      space: 1,
      thickness: 1,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.bgPanel),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
        ),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Almarai',
        fontSize: 13,
        color: AppColors.textHigh,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.bgPanel,
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(
        fontFamily: 'Almarai',
        fontSize: 13,
        color: AppColors.textHigh,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.bgPanel,
      contentTextStyle: TextStyle(color: AppColors.textHigh),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'Almarai',
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.accent : AppColors.textLow,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.accent : AppColors.textLow,
        );
      }),
    ),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(
        fontFamily: 'Almarai',
        color: AppColors.textMid,
        fontWeight: FontWeight.w600,
      ),
      dataTextStyle: TextStyle(
        fontFamily: 'Almarai',
        color: AppColors.textHigh,
      ),
      dividerThickness: 0.5,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMid,
      textColor: AppColors.textHigh,
    ),
    iconTheme: const IconThemeData(color: AppColors.textMid),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
