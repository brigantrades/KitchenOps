import 'package:flutter/material.dart';

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.surfaceBase,
    required this.surfaceAlt,
    required this.panel,
    required this.panelStrong,
    required this.heroStart,
    required this.heroEnd,
    required this.heroAccent,
    required this.pillBg,
    required this.pillBorder,
    required this.highlight,
    required this.highlightSoft,
  });

  final Color surfaceBase;
  final Color surfaceAlt;
  final Color panel;
  final Color panelStrong;
  final Color heroStart;
  final Color heroEnd;
  final Color heroAccent;
  final Color pillBg;
  final Color pillBorder;
  final Color highlight;
  final Color highlightSoft;

  @override
  AppThemeColors copyWith({
    Color? surfaceBase,
    Color? surfaceAlt,
    Color? panel,
    Color? panelStrong,
    Color? heroStart,
    Color? heroEnd,
    Color? heroAccent,
    Color? pillBg,
    Color? pillBorder,
    Color? highlight,
    Color? highlightSoft,
  }) {
    return AppThemeColors(
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      panel: panel ?? this.panel,
      panelStrong: panelStrong ?? this.panelStrong,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      heroAccent: heroAccent ?? this.heroAccent,
      pillBg: pillBg ?? this.pillBg,
      pillBorder: pillBorder ?? this.pillBorder,
      highlight: highlight ?? this.highlight,
      highlightSoft: highlightSoft ?? this.highlightSoft,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelStrong: Color.lerp(panelStrong, other.panelStrong, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      heroAccent: Color.lerp(heroAccent, other.heroAccent, t)!,
      pillBg: Color.lerp(pillBg, other.pillBg, t)!,
      pillBorder: Color.lerp(pillBorder, other.pillBorder, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      highlightSoft: Color.lerp(highlightSoft, other.highlightSoft, t)!,
    );
  }

  static const light = AppThemeColors(
    surfaceBase: Color(0xFFFAFAFA),
    surfaceAlt: Color(0xFFFDF3F1),
    panel: Color(0xFFFFFFFF),
    panelStrong: Color(0xFFFFF2EF),
    heroStart: Color(0xFFFFDAD6),
    heroEnd: Color(0xFFFFAB91),
    heroAccent: Color(0xFFFF6B6B),
    pillBg: Color(0xFFF5F5F5),
    pillBorder: Color(0xFFE9E9E9),
    highlight: Color(0xFFFF6B6B),
    highlightSoft: Color(0xFFFFE6E2),
  );

  static const dark = AppThemeColors(
    surfaceBase: Color(0xFF181A1B),
    surfaceAlt: Color(0xFF1F2224),
    panel: Color(0xFF262A2D),
    panelStrong: Color(0xFF2E3236),
    heroStart: Color(0xFF6D4B4B),
    heroEnd: Color(0xFF7C5A4D),
    heroAccent: Color(0xFFFF8A80),
    pillBg: Color(0xFF2F3438),
    pillBorder: Color(0xFF3E4449),
    highlight: Color(0xFFFF8A80),
    highlightSoft: Color(0xFF4A3533),
  );
}
