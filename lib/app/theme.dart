import 'package:flutter/material.dart';

const gold = Color(0xFFE8B66A);
const ink = Color(0xFF282621);
const muted = Color(0xFF807B73);
const canvas = Color(0xFFFAF9F6);
const line = Color(0xFFECE7DE);
const goldInk = Color(0xFF8D652E);
const goldWash = Color(0xFFFAF0DF);

ThemeData salesTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gold,
    primary: goldInk,
    surface: Colors.white,
    onSurface: ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -.9,
            color: ink,
          ),
          headlineSmall: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 25,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: ink,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 21,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
            color: ink,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            height: 1.5,
            color: ink,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            height: 1.5,
            color: muted,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 24,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: muted,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: muted,
        fontSize: 14,
      ),
      prefixIconColor: muted,
      suffixIconColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: goldInk, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: ink,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: goldInk,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: goldWash,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 12,
        color: muted,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: goldWash,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? goldInk : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? goldInk : muted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: -.4,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: Colors.white,
        fontSize: 13,
        height: 1.5,
      ),
    ),
    dividerTheme: const DividerThemeData(color: line, space: 1, thickness: 1),
  );
}
