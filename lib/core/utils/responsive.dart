/// Responsive layout helpers.
/// Breakpoints: phone < 600dp, tablet >= 600dp.
import 'package:flutter/material.dart';

class Responsive {
  /// 600dp breakpoint — the Material Design standard for phone/tablet.
  static const double tabletBreakpoint = 600;

  /// Whether the current screen is wide enough for tablet layout.
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  /// Returns appropriate cross-axis count for grid layouts.
  static int gridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 4;
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }
}
