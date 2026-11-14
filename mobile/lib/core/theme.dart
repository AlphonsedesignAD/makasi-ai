import 'package:flutter/material.dart';

/// Palette et thème de Makasi AI.
/// Reprend fidèlement l'identité du site : sombre, indigo/violet, sobre.
class MakasiTheme {
  MakasiTheme._();

  static const Color brandStart = Color(0xFF4F46E5);
  static const Color brandMid = Color(0xFF7C3AED);
  static const Color brandEnd = Color(0xFFEC4899);

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandStart, brandMid, brandEnd],
  );

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final bg = dark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
    final surface = dark ? const Color(0xFF17171A) : const Color(0xFFF4F6FB);
    final surface2 = dark ? const Color(0xFF242428) : const Color(0xFFE8EDF6);
    final text = dark ? const Color(0xFFE7E7EA) : const Color(0xFF17181C);
    final muted = dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final line = dark ? const Color(0xFF2D2D32) : const Color(0xFFE3E7EF);
    final accent = dark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
    final onAccent = Colors.white;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: dark ? const Color(0xFF2A2A55) : const Color(0xFFE7E9FF),
      onPrimaryContainer: dark ? const Color(0xFFC7C9FF) : const Color(0xFF26236B),
      secondary: brandMid,
      onSecondary: Colors.white,
      secondaryContainer: dark ? const Color(0xFF35254C) : const Color(0xFFF0E6FF),
      onSecondaryContainer: dark ? const Color(0xFFE9D5FF) : const Color(0xFF4A1D7A),
      tertiary: brandEnd,
      onTertiary: Colors.white,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      surface: bg,
      onSurface: text,
      surfaceContainerLowest: bg,
      surfaceContainerLow: dark ? const Color(0xFF141417) : const Color(0xFFFAFBFD),
      surfaceContainer: surface,
      surfaceContainerHigh: dark ? const Color(0xFF1D1D21) : const Color(0xFFEEF2F9),
      surfaceContainerHighest: surface2,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: dark ? const Color(0xFF232327) : const Color(0xFFEDF0F6),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? const Color(0xFFE7E7EA) : const Color(0xFF1B1B1F),
      onInverseSurface: dark ? const Color(0xFF17171A) : const Color(0xFFF7F7F9),
      inversePrimary: dark ? const Color(0xFF4F46E5) : const Color(0xFFA5B4FC),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      splashFactory: InkRipple.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(fontFamily: 'Inter', bodyColor: text, displayColor: text)
        .copyWith(
          displaySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            color: text,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: text,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
            color: text,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: text,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: text,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15.5,
            height: 1.55,
            letterSpacing: -0.1,
            color: text,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 1.55,
            letterSpacing: -0.05,
            color: text,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            height: 1.45,
            color: muted,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.05,
            color: text,
          ),
          labelMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: muted,
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: muted,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: text, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.75), fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFFE7E7EA) : const Color(0xFF1B1B1F),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: dark ? const Color(0xFF17171A) : const Color(0xFFF7F7F9),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 6,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: line,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.25),
        selectionHandleColor: accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

extension MakasiColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  TextTheme get texts => Theme.of(this).textTheme;
}
