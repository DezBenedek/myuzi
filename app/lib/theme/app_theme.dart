import 'package:flutter/material.dart';

class AppTheme {
  static const brand = Color(0xFF0B6E4F);
  static const brandDark = Color(0xFF084C37);
  static const ink = Color(0xFF12261C);
  static const muted = Color(0xFF4D6358);
  static const soft = Color(0xFFF3F7F4);
  static const danger = Color(0xFFB42318);
  /// Unheard incoming voice note.
  static const unreadYellow = Color(0xFFF5D76E);
  static const unreadYellowDark = Color(0xFFE0B830);

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

    return _base(
      scheme: scheme,
      visionAssist: visionAssist,
      scale: scale,
      weight: weight,
      radius: radius,
      scaffold: visionAssist ? Colors.white : soft,
      card: Colors.white,
      cardBorder: visionAssist ? Colors.black : const Color(0xFFD7E4DC),
      inputFill: Colors.white,
      mutedBody: visionAssist ? Colors.black : muted,
    );
  }

  static ThemeData dark({required bool visionAssist}) {
    final scale = visionAssist ? 1.25 : 1.0;
    final weight = visionAssist ? FontWeight.w800 : FontWeight.w600;
    final radius = visionAssist ? 20.0 : 18.0;
    const surface = Color(0xFF121A16);
    const card = Color(0xFF1B2620);
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
      primary: const Color(0xFF3DCF9A),
      onPrimary: const Color(0xFF003822),
      surface: surface,
      onSurface: visionAssist ? Colors.white : const Color(0xFFE6F2EC),
    );

    return _base(
      scheme: scheme,
      visionAssist: visionAssist,
      scale: scale,
      weight: weight,
      radius: radius,
      scaffold: surface,
      card: card,
      cardBorder: visionAssist ? Colors.white70 : const Color(0xFF2E3F36),
      inputFill: const Color(0xFF24302A),
      mutedBody: visionAssist ? Colors.white : const Color(0xFFA8BDB2),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required bool visionAssist,
    required double scale,
    required FontWeight weight,
    required double radius,
    required Color scaffold,
    required Color card,
    required Color cardBorder,
    required Color inputFill,
    required Color mutedBody,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      cardColor: card,
      dividerColor: cardBorder,
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
        titleMedium: TextStyle(
          fontSize: 16 * scale,
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
          color: mutedBody,
        ),
        labelLarge: TextStyle(
          fontSize: 18 * scale,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 13 * scale,
          fontWeight: FontWeight.w600,
          color: mutedBody,
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
            color: visionAssist
                ? scheme.onSurface
                : scheme.primary,
            width: visionAssist ? 2.5 : 1.5,
          ),
          textStyle: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: visionAssist ? 20 : 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: cardBorder,
            width: visionAssist ? 2 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: cardBorder,
            width: visionAssist ? 2 : 1,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(backgroundColor: card),
      iconTheme: IconThemeData(
        size: visionAssist ? 32 : 26,
        weight: visionAssist ? 800 : 400,
        color: scheme.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(
          visionAssist ? scheme.onSurface : scheme.primary,
        ),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.45);
          }
          return scheme.onSurface.withValues(alpha: 0.2);
        }),
      ),
    );
  }
}
