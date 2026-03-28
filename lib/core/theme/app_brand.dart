import 'package:flutter/material.dart';

/// App-wide brand palette (mint / teal / off‑white).
///
/// Typography uses **Sora** via [GoogleFonts] in [AppTheme] (Satoshi can replace
/// it when font files are added to `pubspec.yaml`).
abstract final class AppBrand {
  static const Color mutedAqua = Color(0xFFB5DDD8);
  static const Color paleMint = Color(0xFFD6EDEA);
  static const Color offWhite = Color(0xFFFCFFFC);
  static const Color black = Color(0xFF000000);

  static const Color deepTeal = Color(0xFF124A40);
  static const Color tealVibrant = Color(0xFF3EB8A8);

  static const Color darkSurface = Color(0xFF152A28);
  static const Color darkOnSurfaceVariant = Color(0xFFA5C5C0);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepTeal, tealVibrant],
  );

  static const LinearGradient headerGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D3833), Color(0xFF2A7A72)],
  );
}
