import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const night = Color(0xFF0E203B);
  static const brand = Color(0xFFFF6A00);
  static const brandSoft = Color(0xFFFFF1E8);
  static const mint = Color(0xFF15C99A);
  static const mintSoft = Color(0xFFE8FBF5);
  static const mist = Color(0xFFF2F5F9);
  static const danger = Color(0xFFE11D48);
  static const dangerSoft = Color(0xFFFFE8EE);
  static const waiting = Color(0xFFF59E0B);
  static const waitingSoft = Color(0xFFFFF6E5);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE6ECF2);
  static const ink = Color(0xFF152033);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.brand, primary: AppColors.brand, surface: Colors.white),
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: AppColors.ink, displayColor: AppColors.night),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: AppColors.night, elevation: 0, scrolledUnderElevation: 0),
    dividerColor: AppColors.line,
  );
}
