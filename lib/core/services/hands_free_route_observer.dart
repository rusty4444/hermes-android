import 'package:flutter/widgets.dart';

/// Synchronous navigation revocation, including PopupRoutes. ModalRoute's
/// dependency is also checked by ChatScreen, for nested/test Navigators.
class HandsFreeRouteObserver extends NavigatorObserver {
  final Set<VoidCallback> _listeners = {};
  Route<dynamic>? _top;
  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  bool permits(Route<dynamic>? route) =>
      navigator == null || identical(_top, route);
  void _changed(Route<dynamic>? top) {
    _top = top;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _top)) _changed(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, _top)) _changed(newRoute);
  }
}

final handsFreeRouteObserver = HandsFreeRouteObserver();
