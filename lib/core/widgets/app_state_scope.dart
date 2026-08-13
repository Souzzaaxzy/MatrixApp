import 'package:flutter/widgets.dart';

import '../services/app_state.dart';

/// InheritedNotifier that exposes [AppState] to the whole widget tree.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required this.state,
    required super.child,
  }) : super(notifier: state);

  final AppState state;

  /// Reads the [AppState] from the nearest [AppStateScope].
  static AppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.state;
  }
}
