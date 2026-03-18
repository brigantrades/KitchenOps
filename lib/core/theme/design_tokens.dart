import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(16));
  static const BorderRadius md = BorderRadius.all(Radius.circular(24));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(32));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(32));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
}

abstract final class AppShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      spreadRadius: 2,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      spreadRadius: 1,
      offset: Offset(0, 10),
    ),
  ];
}
