import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class AppTheme {
  static ColorScheme _lightScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppBrand.deepTeal,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: AppBrand.deepTeal,
      onPrimary: AppBrand.offWhite,
      primaryContainer: AppBrand.paleMint,
      onPrimaryContainer: AppBrand.black,
      secondary: AppBrand.mutedAqua,
      onSecondary: AppBrand.black,
      secondaryContainer: AppBrand.mutedAqua,
      onSecondaryContainer: AppBrand.black,
      tertiary: AppBrand.tealVibrant,
      surface: AppBrand.offWhite,
      onSurface: AppBrand.black,
      onSurfaceVariant: const Color(0xFF4A5F5C),
      outline: AppBrand.mutedAqua,
      outlineVariant: AppBrand.mutedAqua.withValues(alpha: 0.55),
    );
  }

  static ColorScheme _darkScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppBrand.tealVibrant,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: AppBrand.tealVibrant,
      onPrimary: AppBrand.black,
      primaryContainer: const Color(0xFF1A3830),
      onPrimaryContainer: AppBrand.offWhite,
      secondary: AppBrand.mutedAqua,
      onSecondary: AppBrand.black,
      secondaryContainer: const Color(0xFF1F4A44),
      onSecondaryContainer: AppBrand.offWhite,
      tertiary: AppBrand.tealVibrant,
      surface: AppBrand.darkSurface,
      onSurface: AppBrand.offWhite,
      onSurfaceVariant: AppBrand.darkOnSurfaceVariant,
      outline: AppBrand.mutedAqua.withValues(alpha: 0.45),
      outlineVariant: AppBrand.mutedAqua.withValues(alpha: 0.22),
    );
  }

  static TextTheme _soraTextTheme(TextTheme base, Color onSurface) {
    return GoogleFonts.soraTextTheme(base).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
  }

  static ThemeData light() {
    final scheme = _lightScheme();
    final textTheme =
        _soraTextTheme(ThemeData.light().textTheme, scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppBrand.offWhite,
      extensions: const [AppThemeColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: AppBrand.offWhite,
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
        color: AppBrand.offWhite,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppBrand.offWhite,
        indicatorColor: AppBrand.deepTeal.withValues(alpha: 0.15),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppBrand.deepTeal
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppBrand.deepTeal
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: AppBrand.deepTeal,
        unselectedItemColor: scheme.onSurfaceVariant,
        backgroundColor: AppBrand.offWhite,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: AppBrand.paleMint,
        selectedColor: AppBrand.mutedAqua,
        secondarySelectedColor: AppBrand.mutedAqua,
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: AppBrand.black),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? AppBrand.mutedAqua
                : AppBrand.paleMint,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? AppBrand.black
                : scheme.onSurfaceVariant,
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppBrand.offWhite,
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
          borderSide: BorderSide(color: AppBrand.deepTeal, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppBrand.mutedAqua,
          foregroundColor: AppBrand.black,
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge?.copyWith(color: AppBrand.black),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 50),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(color: AppBrand.black),
          backgroundColor: AppBrand.mutedAqua,
          foregroundColor: AppBrand.black,
          disabledBackgroundColor: AppBrand.mutedAqua.withValues(alpha: 0.45),
          disabledForegroundColor: AppBrand.black.withValues(alpha: 0.45),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppBrand.mutedAqua,
        foregroundColor: AppBrand.black,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.hero),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppBrand.offWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        backgroundColor: AppBrand.offWhite,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = _darkScheme();
    final textTheme =
        _soraTextTheme(ThemeData.dark().textTheme, scheme.onSurface);
    final fillBg = AppBrand.mutedAqua.withValues(alpha: 0.85);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppBrand.darkSurface,
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
        selectedColor: AppBrand.mutedAqua.withValues(alpha: 0.55),
        secondarySelectedColor: AppBrand.mutedAqua.withValues(alpha: 0.55),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: AppBrand.offWhite),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? AppBrand.mutedAqua.withValues(alpha: 0.55)
                : scheme.surfaceContainerHighest,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? AppBrand.offWhite
                : scheme.onSurfaceVariant,
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.75)),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: fillBg,
          foregroundColor: AppBrand.black,
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge?.copyWith(color: AppBrand.black),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: textTheme.labelLarge?.copyWith(color: AppBrand.black),
          backgroundColor: fillBg,
          foregroundColor: AppBrand.black,
          disabledBackgroundColor: fillBg.withValues(alpha: 0.45),
          disabledForegroundColor: AppBrand.black.withValues(alpha: 0.45),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fillBg,
        foregroundColor: AppBrand.black,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.hero),
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
