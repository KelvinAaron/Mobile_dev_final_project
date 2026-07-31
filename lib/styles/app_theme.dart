import 'package:flutter/material.dart';

class FinmoTheme {
  static const _yellow = Color(0xFFFFCC00);
  static const _lightBackground = Color(0xFFFEF3C7);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightText = Color(0xFF1F2937);
  static const _lightMuted = Color(0xFF6B7280);

  // Derived only from the supplied design: near-black page, navy cards and
  // inputs, warm yellow actions, white primary text, and muted grey labels.
  static const _darkBackground = Color(0xFF101419);
  static const _darkSurface = Color(0xFF181E27);
  static const _darkInput = Color(0xFF202735);
  static const _darkText = Color(0xFFF9FAFB);
  static const _darkMuted = Color(0xFF9CA3AF);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: _lightBackground,
        surface: _lightSurface,
        input: const Color(0xFFF9FAFB),
        text: _lightText,
        muted: _lightMuted,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: _darkBackground,
        surface: _darkSurface,
        input: _darkInput,
        text: _darkText,
        muted: _darkMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color input,
    required Color text,
    required Color muted,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: _yellow,
      onPrimary: const Color(0xFF111827),
      secondary: _yellow,
      onSecondary: const Color(0xFF111827),
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: input,
      onSurfaceVariant: muted,
      outline: brightness == Brightness.dark
          ? const Color(0xFF374151)
          : const Color(0xFFE5E7EB),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      dividerColor: scheme.outline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _yellow),
        ),
      ),
      cardTheme: CardThemeData(color: surface),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: _yellow,
        unselectedItemColor: muted,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: _yellow,
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF202938)
            : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
