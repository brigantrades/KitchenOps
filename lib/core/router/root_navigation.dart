import 'package:flutter/material.dart';

/// Shared with [GoRouter] and push notification handlers so we can navigate
/// without a [BuildContext] from a widget.
final rootNavigatorKey = GlobalKey<NavigatorState>();
