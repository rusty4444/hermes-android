/// The Hermes Android design system.
///
/// One typed token layer that every screen consumes, so spacing, radius,
/// motion, semantic status colors, and the typography ramp are decided once
/// instead of per screen. See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`
/// ("Interface overhaul") for the product rationale.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The 4dp spacing grid shared by every Hermes surface.
abstract final class HermesSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii, growing from small controls to full sheets.
abstract final class HermesRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Motion budget. Animations exist to explain a change, never to decorate.
abstract final class HermesMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 320);

  static const Curve curve = Curves.easeOutCubic;
}

/// Semantic state of a chat, task, or activity item.
enum HermesStatus {
  /// Work is actively progressing.
  running,

  /// Hermes cannot continue without the user (approval, clarify, secret).
  blocked,

  /// Work ended in an error.
  failed,

  /// Work ended successfully.
  completed,

  /// Nothing is happening.
  idle,
}

/// The Hermes typography ramp.
///
/// [mono] owns code, file paths, and terminal output; everything else is prose.
class HermesTypography {
  final TextStyle display;
  final TextStyle title;
  final TextStyle section;
  final TextStyle body;
  final TextStyle label;
  final TextStyle mono;

  const HermesTypography({
    required this.display,
    required this.title,
    required this.section,
    required this.body,
    required this.label,
    required this.mono,
  });

  static HermesTypography ramp(Brightness brightness) {
    return const HermesTypography(
      display: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      title: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      section: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      body: TextStyle(fontSize: 14, height: 1.45),
      label: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      mono: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontFamily: 'monospace',
        fontFamilyFallback: ['monospace'],
      ),
    );
  }

  TextTheme applyTo(TextTheme base, Color onSurface, Color muted) {
    return base.copyWith(
      headlineSmall: display.copyWith(color: onSurface),
      titleLarge: title.copyWith(color: onSurface),
      titleMedium: section.copyWith(color: onSurface),
      bodyMedium: body.copyWith(color: onSurface),
      bodySmall: body.copyWith(color: muted),
      labelMedium: label.copyWith(color: muted),
    );
  }
}

/// The Hermes design tokens, carried on [ThemeData.extensions].
@immutable
class HermesTokens extends ThemeExtension<HermesTokens> {
  /// The Hermes brand accent, identical in both themes.
  static const Color hermesGold = Color(0xFFD4AF37);

  final Brightness brightness;
  final Color surface;
  final Color raised;
  final Color border;
  final Color onSurface;
  final Color muted;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color running;
  final Color blocked;
  final HermesTypography typography;

  const HermesTokens({
    required this.brightness,
    required this.surface,
    required this.raised,
    required this.border,
    required this.onSurface,
    required this.muted,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.running,
    required this.blocked,
    required this.typography,
  });

  factory HermesTokens.dark() {
    return HermesTokens(
      brightness: Brightness.dark,
      surface: const Color(0xFF0E0E10),
      raised: const Color(0xFF1A1A1D),
      border: const Color(0xFF2A2A2F),
      onSurface: const Color(0xFFF2F2F3),
      muted: const Color(0xFFA3A3AA),
      accent: hermesGold,
      success: const Color(0xFF4ADE80),
      warning: const Color(0xFFFBBF24),
      danger: const Color(0xFFF87171),
      running: const Color(0xFF60A5FA),
      blocked: const Color(0xFFF59E0B),
      typography: HermesTypography.ramp(Brightness.dark),
    );
  }

  factory HermesTokens.light() {
    return HermesTokens(
      brightness: Brightness.light,
      surface: const Color(0xFFFAFAFA),
      raised: const Color(0xFFFFFFFF),
      border: const Color(0xFFE2E2E5),
      onSurface: const Color(0xFF17171A),
      muted: const Color(0xFF5F5F68),
      accent: hermesGold,
      success: const Color(0xFF15803D),
      warning: const Color(0xFFB45309),
      danger: const Color(0xFFB91C1C),
      running: const Color(0xFF1D4ED8),
      blocked: const Color(0xFF9A5B00),
      typography: HermesTypography.ramp(Brightness.light),
    );
  }

  static HermesTokens forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? HermesTokens.dark()
        : HermesTokens.light();
  }

  /// The tokens for the closest theme, falling back to a matching set when a
  /// widget is mounted under a plain [ThemeData] (tests, previews, plugins).
  static HermesTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HermesTokens>() ??
        HermesTokens.forBrightness(theme.brightness);
  }

  Color colorForStatus(HermesStatus status) {
    switch (status) {
      case HermesStatus.running:
        return running;
      case HermesStatus.blocked:
        return blocked;
      case HermesStatus.failed:
        return danger;
      case HermesStatus.completed:
        return success;
      case HermesStatus.idle:
        return muted;
    }
  }

  @override
  HermesTokens copyWith({
    Brightness? brightness,
    Color? surface,
    Color? raised,
    Color? border,
    Color? onSurface,
    Color? muted,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? running,
    Color? blocked,
    HermesTypography? typography,
  }) {
    return HermesTokens(
      brightness: brightness ?? this.brightness,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      border: border ?? this.border,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      running: running ?? this.running,
      blocked: blocked ?? this.blocked,
      typography: typography ?? this.typography,
    );
  }

  @override
  HermesTokens lerp(ThemeExtension<HermesTokens>? other, double t) {
    if (other is! HermesTokens) return this;
    return HermesTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      running: Color.lerp(running, other.running, t)!,
      blocked: Color.lerp(blocked, other.blocked, t)!,
      typography: t < 0.5 ? typography : other.typography,
    );
  }
}

/// Builds the Hermes [ThemeData] for one brightness, tokens attached.
ThemeData hermesTheme(Brightness brightness) {
  final tokens = HermesTokens.forBrightness(brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: HermesTokens.hermesGold,
        brightness: brightness,
      ).copyWith(
        surface: tokens.surface,
        onSurface: tokens.onSurface,
        error: tokens.danger,
        outlineVariant: tokens.border,
      );

  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  );

  return base.copyWith(
    scaffoldBackgroundColor: tokens.surface,
    textTheme: tokens.typography.applyTo(
      base.textTheme,
      tokens.onSurface,
      tokens.muted,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: tokens.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: HermesRadius.card,
        side: BorderSide(color: tokens.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      space: 1,
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.accent,
      foregroundColor: Colors.black,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.raised,
      shape: const RoundedRectangleBorder(borderRadius: HermesRadius.sheet),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.raised,
      contentTextStyle: tokens.typography.body.copyWith(
        color: tokens.onSurface,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    // The bar must keep every label on one line. At the 12sp label ramp the
    // longest catalogue entries overflow their destination and wrap — ja
    // アクティビティ (seven glyphs) is the first to go. 11sp with no tracking
    // fits the widest shipped labels while staying legible.
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return tokens.typography.label.copyWith(
          fontSize: 11,
          letterSpacing: 0,
          height: 1.2,
          color: states.contains(WidgetState.selected)
              ? tokens.onSurface
              : tokens.muted,
        );
      }),
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}

/// WCAG 2.1 relative luminance contrast ratio between two opaque colors.
///
/// Exposed so accessibility expectations live in tests rather than in review
/// opinions: body text must clear 4.5:1 and secondary text 3:1.
double contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(foreground);
  final b = _relativeLuminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
