import 'package:flutter/material.dart';

class AppTheme {
  static const brand = Color(0xFF0B6E4F);
  static const brandDark = Color(0xFF084C37);
  static const ink = Color(0xFF12261C);
  static const muted = Color(0xFF4D6358);
  static const soft = Color(0xFFF3F7F4);
  static const danger = Color(0xFFB42318);

  static ThemeData light({required bool visionAssist}) {
    final scale = visionAssist ? 1.25 : 1.0;
    final weight = visionAssist ? FontWeight.w800 : FontWeight.w600;
    final radius = visionAssist ? 20.0 : 18.0;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      primary: visionAssist ? brandDark : brand,
      onPrimary: Colors.white,
      surface: visionAssist ? Colors.white : soft,
      onSurface: visionAssist ? Colors.black : ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: visionAssist ? Colors.white : soft,
      fontFamily: 'Segoe UI',
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 40 * scale,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          fontSize: 26 * scale,
          fontWeight: weight,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 22 * scale,
          fontWeight: weight,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 18 * scale,
          fontWeight: visionAssist ? FontWeight.w700 : FontWeight.w500,
          color: scheme.onSurface,
          height: 1.3,
        ),
        bodyMedium: TextStyle(
          fontSize: 16 * scale,
          fontWeight: visionAssist ? FontWeight.w600 : FontWeight.w400,
          color: visionAssist ? Colors.black : muted,
        ),
        labelLarge: TextStyle(
          fontSize: 18 * scale,
          fontWeight: FontWeight.w800,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22 * scale,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(visionAssist ? 64 : 56),
          textStyle: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(visionAssist ? 64 : 56),
          side: BorderSide(
            color: visionAssist ? Colors.black : brand,
            width: visionAssist ? 2.5 : 1.5,
          ),
          textStyle: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: visionAssist ? 20 : 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: visionAssist ? Colors.black : const Color(0xFFD7E4DC),
            width: visionAssist ? 2 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: visionAssist ? Colors.black : const Color(0xFFD7E4DC),
            width: visionAssist ? 2 : 1,
          ),
        ),
      ),
      iconTheme: IconThemeData(
        size: visionAssist ? 32 : 26,
        weight: visionAssist ? 800 : 400,
        color: scheme.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(visionAssist ? Colors.black : brand),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return visionAssist ? const Color(0xFF9EE0C3) : const Color(0xFFB7E4D0);
          }
          return Colors.grey.shade300;
        }),
      ),
    );
  }
}
