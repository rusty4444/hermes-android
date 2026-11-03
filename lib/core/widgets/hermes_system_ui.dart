import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/hermes_theme.dart';

/// Own the pixels behind button navigation instead of relying on Android's
/// scrim, whose icon tint can follow the OS rather than the app's forced mode.
class HermesSystemUi extends StatelessWidget {
  const HermesSystemUi({required this.child, this.cinema = false, super.key});

  final Widget child;
  final bool cinema;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final paintsNavigation =
        defaultTargetPlatform == TargetPlatform.android &&
        media.viewPadding.bottom > 0 &&
        media.systemGestureInsets.left == 0 &&
        media.systemGestureInsets.right == 0;
    var style = hermesSystemUiStyle(
      HermesTokens.of(context),
      navigationBrightness: media.platformBrightness,
    ).copyWith(systemNavigationBarContrastEnforced: !paintsNavigation);
    if (cinema) {
      style = style.copyWith(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (paintsNavigation)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: media.viewPadding.bottom,
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('hermes_system_navigation_surface'),
                  color: style.systemNavigationBarColor!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
