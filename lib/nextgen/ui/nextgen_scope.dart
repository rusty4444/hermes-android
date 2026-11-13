// What every NextGen screen needs: the shared connection store, preferences,
// the gateway in use and the actions that change it.
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/connection_manager.dart';
import '../data/nextgen_gateway.dart';

class NgScope extends InheritedWidget {
  const NgScope({
    super.key,
    required this.connManager,
    required this.gateway,
    required this.connections,
    required this.switchTo,
    required this.addGateway,
    required this.signOut,
    required this.reload,
    required this.signInAgain,
    required super.child,
  });

  final ConnectionManager connManager;
  final NextGenGateway gateway;
  final List<SavedConnection> connections;

  /// Switches NextGen to another saved gateway.
  final Future<void> Function(String connectionId) switchTo;

  /// Opens the connect flow to add a gateway.
  final Future<void> Function() addGateway;

  /// Signs out of (and forgets) a gateway.
  final Future<void> Function(SavedConnection connection) signOut;

  /// Re-reads saved connections (after editing them elsewhere).
  final Future<void> Function() reload;

  /// Opens the sign-in flow for the gateway in use.
  final Future<void> Function() signInAgain;

  SharedPreferences get prefs => connManager.prefs;
  SavedConnection get connection => gateway.connection;

  static NgScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NgScope>();
    assert(scope != null, 'No NgScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(NgScope oldWidget) =>
      oldWidget.gateway != gateway || oldWidget.connections != connections;
}
