import 'package:flutter/material.dart';

class MalvaColors {
  const MalvaColors._();

  static const seed = Color(0xFF8E44AD);
  static const plum = Color(0xFF5D2E7E);
  static const orchid = Color(0xFFB65ACB);
  static const pink = Color(0xFFE58BE8);
  static const mint = Color(0xFF36C7A6);
  static const amber = Color(0xFFFFBE55);
  static const danger = Color(0xFFE53935);
  static const ink = Color(0xFF201B24);
  static const paper = Color(0xFFFCFAFD);
}

ThemeData buildMalvaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MalvaColors.seed,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: MalvaColors.seed,
      secondary: MalvaColors.mint,
      error: MalvaColors.danger,
      surface: MalvaColors.paper,
    ),
    scaffoldBackgroundColor: MalvaColors.paper,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF6F1F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

ThemeData buildMalvaDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MalvaColors.seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: MalvaColors.orchid,
      secondary: MalvaColors.mint,
      error: MalvaColors.danger,
      surface: const Color(0xFF1A1520),
    ),
    scaffoldBackgroundColor: const Color(0xFF121015),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: const Color(0xFF1E1A24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2A2432),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}
