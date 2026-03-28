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
    surfaceBase: Color(0xFFFCFFFC),
    surfaceAlt: Color(0xFFD6EDEA),
    panel: Color(0xFFFCFFFC),
    panelStrong: Color(0xFFD6EDEA),
    heroStart: Color(0xFF124A40),
    heroEnd: Color(0xFF3EB8A8),
    heroAccent: Color(0xFF3EB8A8),
    pillBg: Color(0xFFD6EDEA),
    pillBorder: Color(0xFFB5DDD8),
    highlight: Color(0xFF124A40),
    highlightSoft: Color(0xFFD6EDEA),
  );

  static const dark = AppThemeColors(
    surfaceBase: Color(0xFF152A28),
    surfaceAlt: Color(0xFF1A3830),
    panel: Color(0xFF1F2E2C),
    panelStrong: Color(0xFF1F4A44),
    heroStart: Color(0xFF0D3833),
    heroEnd: Color(0xFF2A7A72),
    heroAccent: Color(0xFF3EB8A8),
    pillBg: Color(0xFF1F4A44),
    pillBorder: Color(0xFF2A7A72),
    highlight: Color(0xFF3EB8A8),
    highlightSoft: Color(0xFF1F4A44),
  );
}
