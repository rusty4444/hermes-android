/// The Hermes Android design system.
///
/// One typed token layer that every screen consumes, so spacing, radius,
/// motion, semantic status colors, and the typography ramp are decided once
/// instead of per screen. See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`
/// ("Interface overhaul") for the product rationale.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Complete palettes, not accent-only overrides. Persist [name], never [index].
/// Seeds identify the palette; accessible foregrounds use brightness-aware tones.
enum HermesPalette {
  gold('Gold', Color(0xFFD4AF37)),
  purple('Purple', Color(0xFF9C6ADE)),
  orange('Orange', Color(0xFFF28C28)),
  green('Green', Color(0xFF22A06B)),
  blue('Blue', Color(0xFF3B82F6)),
  red('Red', Color(0xFFE5484D)),
  teal('Teal', Color(0xFF14B8A6)),
  pink('Pink', Color(0xFFEC4899)),
  indigo('Indigo', Color(0xFF6366F1)),
  cyan('Cyan', Color(0xFF06B6D4));

  const HermesPalette(this.displayName, this.seedColor);

  final String displayName;
  final Color seedColor;
}

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
  /// The original seed and dark gold accent, not a readable light-mode ink.
  static const Color hermesGold = Color(0xFFD4AF37);

  final Brightness brightness;
  final HermesPalette palette;
  final Color surface;
  final Color raised;
  final Color border;
  final Color onSurface;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color success;
  final Color warning;
  final Color danger;
  final Color running;
  final Color blocked;
  final HermesTypography typography;

  const HermesTokens({
    required this.brightness,
    this.palette = HermesPalette.gold,
    required this.surface,
    required this.raised,
    required this.border,
    required this.onSurface,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.success,
    required this.warning,
    required this.danger,
    required this.running,
    required this.blocked,
    required this.typography,
  });

  factory HermesTokens.dark({HermesPalette palette = HermesPalette.gold}) =>
      HermesTokens.forBrightness(Brightness.dark, palette: palette);

  factory HermesTokens.light({HermesPalette palette = HermesPalette.gold}) =>
      HermesTokens.forBrightness(Brightness.light, palette: palette);

  static HermesTokens forBrightness(
    Brightness brightness, {
    HermesPalette palette = HermesPalette.gold,
  }) => HermesTokens._fromScheme(
    _hermesColorScheme(brightness, palette),
    palette,
  );

  factory HermesTokens._fromScheme(ColorScheme scheme, HermesPalette palette) {
    final dark = scheme.brightness == Brightness.dark;
    return HermesTokens(
      brightness: scheme.brightness,
      palette: palette,
      surface: scheme.surface,
      raised: scheme.surfaceContainerLow,
      border: scheme.outlineVariant,
      onSurface: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      accentContainer: scheme.primaryContainer,
      onAccentContainer: scheme.onPrimaryContainer,
      // Status meanings do not rotate with the decorative palette. Use darker
      // inks in light mode, including on the tinted status-badge backgrounds.
      success: dark ? const Color(0xFF4ADE80) : const Color(0xFF166534),
      warning: dark ? const Color(0xFFFBBF24) : const Color(0xFF854D0E),
      danger: scheme.error,
      running: dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      blocked: dark ? const Color(0xFFF59E0B) : const Color(0xFF92400E),
      typography: HermesTypography.ramp(scheme.brightness),
    );
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
    HermesPalette? palette,
    Color? surface,
    Color? raised,
    Color? border,
    Color? onSurface,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? success,
    Color? warning,
    Color? danger,
    Color? running,
    Color? blocked,
    HermesTypography? typography,
  }) {
    return HermesTokens(
      brightness: brightness ?? this.brightness,
      palette: palette ?? this.palette,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      border: border ?? this.border,
      onSurface: onSurface ?? this.onSurface,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
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
      palette: t < 0.5 ? palette : other.palette,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(
        onAccentContainer,
        other.onAccentContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      running: Color.lerp(running, other.running, t)!,
      blocked: Color.lerp(blocked, other.blocked, t)!,
      typography: t < 0.5 ? typography : other.typography,
    );
  }
}

ColorScheme _hermesColorScheme(Brightness brightness, HermesPalette palette) {
  // Generate every role together: secondary/tertiary, all container levels,
  // inverse surfaces, outlines, and their foregrounds share the chosen hue.
  // Medium contrast also leaves headroom for the app's 8–18% selected tints
  // and for normal-size muted labels, rather than only testing large text.
  final generated = ColorScheme.fromSeed(
    seedColor: palette.seedColor,
    brightness: brightness,
    contrastLevel: 0.5,
  );
  final accent = brightness == Brightness.dark && palette == HermesPalette.gold
      ? HermesTokens.hermesGold
      : generated.primary;
  return generated.copyWith(
    primary: accent,
    onPrimary: foregroundFor(accent),
    surfaceTint: accent,
  );
}

/// Builds a complete Hermes [ThemeData], with matching tokens attached.
ThemeData hermesTheme(
  Brightness brightness, {
  HermesPalette palette = HermesPalette.gold,
}) {
  final scheme = _hermesColorScheme(brightness, palette);
  final tokens = HermesTokens._fromScheme(scheme, palette);
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  );
  final selectedSurface = Color.alphaBlend(
    tokens.accent.withValues(alpha: 0.18),
    tokens.raised,
  );
  final selectedForeground = WidgetStateProperty.resolveWith<Color>((states) {
    return states.contains(WidgetState.selected) ? tokens.accent : tokens.muted;
  });
  final menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(tokens.raised),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  );
  final inputTheme = InputDecorationThemeData(
    filled: true,
    fillColor: tokens.raised,
    labelStyle: TextStyle(color: tokens.muted),
    floatingLabelStyle: TextStyle(color: tokens.accent),
    hintStyle: TextStyle(color: tokens.muted),
    helperStyle: TextStyle(color: tokens.muted),
    errorStyle: TextStyle(color: tokens.danger),
    prefixIconColor: tokens.muted,
    suffixIconColor: tokens.muted,
    border: OutlineInputBorder(
      borderRadius: HermesRadius.card,
      borderSide: BorderSide(color: tokens.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: HermesRadius.card,
      borderSide: BorderSide(color: tokens.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: HermesRadius.card,
      borderSide: BorderSide(color: tokens.accent, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: HermesRadius.card,
      borderSide: BorderSide(color: tokens.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: HermesRadius.card,
      borderSide: BorderSide(color: tokens.danger, width: 2),
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: tokens.surface,
    canvasColor: tokens.surface,
    disabledColor: tokens.muted,
    textTheme: tokens.typography.applyTo(
      base.textTheme,
      tokens.onSurface,
      tokens.muted,
    ),
    // Keep the base IconTheme: globally replacing its color overrides the
    // correct onPrimary/onSecondaryContainer defaults of filled IconButtons.
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      systemOverlayStyle: hermesSystemUiStyle(tokens),
      foregroundColor: tokens.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: tokens.raised,
      surfaceTintColor: Colors.transparent,
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        disabledBackgroundColor: tokens.raised,
        disabledForegroundColor: tokens.muted,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        disabledBackgroundColor: tokens.raised,
        disabledForegroundColor: tokens.muted,
        surfaceTintColor: Colors.transparent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.accent,
        disabledForegroundColor: tokens.muted,
        side: BorderSide(color: tokens.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.accent,
        disabledForegroundColor: tokens.muted,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.accent,
      foregroundColor: tokens.onAccent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accentContainer
              : tokens.raised;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.onAccentContainer
              : tokens.onSurface;
        }),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.border;
        if (states.contains(WidgetState.error)) return tokens.danger;
        return states.contains(WidgetState.selected)
            ? tokens.accent
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.error)
            ? foregroundFor(tokens.danger)
            : tokens.onAccent;
      }),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BorderSide.none;
        return BorderSide(
          color: states.contains(WidgetState.error)
              ? tokens.danger
              : tokens.muted,
          width: 2,
        );
      }),
    ),
    radioTheme: RadioThemeData(fillColor: selectedForeground),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? tokens.accent
            : tokens.raised;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? tokens.onAccent
            : tokens.muted;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : tokens.muted;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tokens.accent,
      inactiveTrackColor: tokens.border,
      thumbColor: tokens.accent,
      overlayColor: tokens.accent.withValues(alpha: 0.12),
      valueIndicatorColor: tokens.accent,
      valueIndicatorTextStyle: TextStyle(color: tokens.onAccent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accent,
      linearTrackColor: tokens.border,
      circularTrackColor: tokens.border,
      refreshBackgroundColor: tokens.raised,
    ),
    inputDecorationTheme: inputTheme,
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: tokens.onSurface),
      inputDecorationTheme: inputTheme,
      menuStyle: menuStyle,
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(tokens.raised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(TextStyle(color: tokens.onSurface)),
      hintStyle: WidgetStatePropertyAll(TextStyle(color: tokens.muted)),
    ),
    searchViewTheme: SearchViewThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      headerTextStyle: TextStyle(color: tokens.onSurface),
      headerHintStyle: TextStyle(color: tokens.muted),
      dividerColor: tokens.border,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.raised,
      modalBackgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: tokens.muted,
      shape: const RoundedRectangleBorder(borderRadius: HermesRadius.sheet),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: tokens.typography.title.copyWith(color: tokens.onSurface),
      contentTextStyle: tokens.typography.body.copyWith(
        color: tokens.onSurface,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.raised,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: tokens.onSurface),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(color: tokens.onSurface),
      ),
      iconColor: tokens.muted,
    ),
    menuTheme: MenuThemeData(style: menuStyle),
    menuBarTheme: MenuBarThemeData(style: menuStyle),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? selectedSurface
              : Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.onSurface;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.muted;
        }),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(HermesRadius.sm),
      ),
      textStyle: tokens.typography.label.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.raised,
      contentTextStyle: tokens.typography.body.copyWith(
        color: tokens.onSurface,
      ),
      actionTextColor: tokens.accent,
      disabledActionTextColor: tokens.muted,
      closeIconColor: tokens.muted,
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: 0.24),
      selectionHandleColor: tokens.accent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.accent,
      unselectedLabelColor: tokens.muted,
      indicatorColor: tokens.accent,
      dividerColor: tokens.border,
    ),
    listTileTheme: ListTileThemeData(
      textColor: tokens.onSurface,
      iconColor: tokens.muted,
      selectedColor: tokens.accent,
      selectedTileColor: selectedSurface,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.raised,
      selectedColor: selectedSurface,
      secondarySelectedColor: selectedSurface,
      disabledColor: tokens.raised,
      labelStyle: TextStyle(color: tokens.onSurface),
      secondaryLabelStyle: TextStyle(color: tokens.onSurface),
      checkmarkColor: tokens.accent,
      deleteIconColor: tokens.muted,
      iconTheme: IconThemeData(color: tokens.accent, size: 18),
      surfaceTintColor: Colors.transparent,
      side: BorderSide(color: tokens.border),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: selectedSurface,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(color: selectedForeground.resolve(states));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return tokens.typography.body.copyWith(
          color: selectedForeground.resolve(states),
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: selectedSurface,
      selectedIconTheme: IconThemeData(color: tokens.accent),
      unselectedIconTheme: IconThemeData(color: tokens.muted),
      selectedLabelTextStyle: tokens.typography.label.copyWith(
        color: tokens.accent,
      ),
      unselectedLabelTextStyle: tokens.typography.label.copyWith(
        color: tokens.muted,
      ),
    ),
    // The bar must keep every label on one line. 11sp with no tracking fits
    // the widest shipped labels; the shell further adapts for narrow phones.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: selectedSurface,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(color: selectedForeground.resolve(states));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return tokens.typography.label.copyWith(
          fontSize: 11,
          letterSpacing: 0,
          height: 1.2,
          color: selectedForeground.resolve(states),
        );
      }),
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}

/// Theme Android navigation chrome independently of the operating-system mode.
/// Modern edge-to-edge Android ignores bar fills; Flutter draws the themed
/// surface behind gesture navigation. Preserve Android's protective scrim for
/// three-button navigation: OEMs can override icon tint from the OS mode.
SystemUiOverlayStyle hermesSystemUiStyle(
  HermesTokens tokens, {
  Brightness? navigationBrightness,
}) {
  final icons = tokens.brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  // Some Android versions tint three-button controls from the OS theme even
  // when a different foreground is requested. Match the navigation fill and
  // protective scrim to that mode; status icons still follow the app's mode.
  final nativeBrightness = navigationBrightness ?? tokens.brightness;
  final navigationScheme = _hermesColorScheme(nativeBrightness, tokens.palette);
  final navigationIcons = nativeBrightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: tokens.brightness,
    statusBarIconBrightness: icons,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: navigationScheme.surface,
    systemNavigationBarDividerColor: navigationScheme.surface,
    systemNavigationBarIconBrightness: navigationIcons,
    systemNavigationBarContrastEnforced: true,
  );
}

/// Whichever opaque black/white foreground has the higher WCAG contrast.
/// Composite translucent backgrounds onto their actual surface before calling.
Color foregroundFor(Color background) {
  return contrastRatio(Colors.black, background) >=
          contrastRatio(Colors.white, background)
      ? Colors.black
      : Colors.white;
}

/// WCAG relative luminance contrast ratio between two opaque colors.
/// Normal-size body, secondary, and accent text must all clear 4.5:1.
/// Composite translucent colors onto their actual background before measuring.
double contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(foreground);
  final b = _relativeLuminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
