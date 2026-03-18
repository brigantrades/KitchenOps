import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class AppTheme {
  static const _seed = Color(0xFFFF6B6B);

  static const _lightBackground = Color(0xFFFAFAFA);
  static const _lightSurface = Colors.white;
  static const _lightOnSurface = Color(0xFF2D3436);
  static const _lightSurfaceVariant = Color(0xFFF5F5F5);
  static const _lightOnSurfaceVariant = Color(0xFF636E72);

  static TextTheme _poppinsTextTheme(TextTheme base, Color onSurface) {
    final text = GoogleFonts.poppinsTextTheme(base).apply(
      fontFamily: GoogleFonts.poppins().fontFamily,
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    return text.copyWith(
      headlineLarge: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.1,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.15,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      labelLarge: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
    );
  }

  static ColorScheme _lightScheme() {
    return ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light)
        .copyWith(
      primary: const Color(0xFFFF6B6B),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFDAD6),
      secondary: const Color(0xFF4ECDC4),
      onSecondary: Colors.white,
      tertiary: const Color(0xFFFFAB91),
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      surfaceContainerHighest: _lightSurfaceVariant,
      onSurfaceVariant: _lightOnSurfaceVariant,
    );
  }

  static ThemeData light() {
    final scheme = _lightScheme();
    final textTheme =
        _poppinsTextTheme(ThemeData.light().textTheme, scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _lightBackground,
      extensions: const [AppThemeColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: _lightSurface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 2.5,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        margin: EdgeInsets.zero,
        color: _lightSurface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        backgroundColor: _lightSurface,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: _lightSurfaceVariant,
        selectedColor: scheme.secondary,
        secondarySelectedColor: scheme.secondary,
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: scheme.onSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.sm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.sm,
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.sm,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 50),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.hero),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        backgroundColor: _lightSurface,
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark)
            .copyWith(
      primary: const Color(0xFFFF8A80),
      secondary: const Color(0xFF4ECDC4),
      tertiary: const Color(0xFFFFAB91),
    );
    final textTheme =
        _poppinsTextTheme(ThemeData.dark().textTheme, scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppThemeColors.dark.surfaceBase,
      extensions: const [AppThemeColors.dark],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.secondary,
        secondarySelectedColor: scheme.secondary,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: scheme.onSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.hero),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
    );
  }
}
