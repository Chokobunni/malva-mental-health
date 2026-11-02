import 'package:flutter/material.dart';

import '../theme.dart';

/// Ambang lebar layar untuk tata letak web.
///
/// Angka ini dipakai bersama oleh shell dan layar autentikasi supaya titik
/// patah (breakpoint) konsisten: panel merek muncul >= 900 px, sidebar tetap
/// muncul >= 1024 px.
abstract final class WebBreakpoints {
  /// Lebar minimum agar panel merek (kiri) ikut ditampilkan.
  static const double splitPanel = 900;

  /// Lebar minimum agar sidebar selalu terlihat (di bawahnya memakai drawer).
  static const double desktop = 1024;

  /// Lebar maksimum area konten agar baris teks tidak terlalu panjang.
  static const double contentMaxWidth = 1280;

  /// Lebar sidebar tetap.
  static const double sidebarWidth = 248;
}

/// Jarak (padding) standar tata letak web.
abstract final class WebSpacing {
  /// Padding horizontal konten di layar desktop.
  static const double gutterDesktop = 32;

  /// Padding horizontal konten di jendela browser sempit (< 600 px).
  static const double gutterCompact = 16;

  /// Jarak antar bagian halaman.
  static const double section = 24;

  /// Padding dalam kartu.
  static const double card = 20;

  /// Jarak antar kartu dalam satu baris.
  static const double cardGap = 16;

  /// Radius sudut kartu web (lebih tegas daripada mobile).
  static const double radius = 16;
}

/// Tema khusus web.
///
/// Palet tetap memakai [MalvaColors] agar identitas merek sama dengan mobile,
/// tetapi tipografi dan bentuk dibuat lebih "desktop": judul lebih besar,
/// kartu bersudut 16, tombol tidak melebar penuh, dan input bergaris halus.
ThemeData buildMalvaWebTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MalvaColors.seed,
    brightness: Brightness.light,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: MalvaColors.seed,
      secondary: MalvaColors.mint,
      error: MalvaColors.danger,
      surface: MalvaColors.paper,
    ),
    scaffoldBackgroundColor: MalvaColors.paper,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        color: MalvaColors.ink,
        height: 1.15,
      ),
      headlineMedium: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: MalvaColors.ink,
        height: 1.2,
      ),
      headlineSmall: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: MalvaColors.ink,
      ),
      titleLarge: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: MalvaColors.ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: MalvaColors.ink,
      ),
      bodyLarge: const TextStyle(
        fontSize: 15,
        height: 1.5,
        color: MalvaColors.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.5,
        color: Color(0xFF5A5260),
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        side: const BorderSide(color: Color(0xFFEDE6F1)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: Color(0xFFE0D6E8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MalvaColors.plum,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7F3FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEADFF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MalvaColors.seed, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MalvaColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MalvaColors.danger, width: 1.6),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: MalvaColors.plum,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFEDE6F1),
      thickness: 1,
      space: 1,
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    tooltipTheme:
        const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
  );
}
