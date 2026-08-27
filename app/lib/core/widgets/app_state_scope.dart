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

  /// Reads the [AppState] from the nearest [AppStateScope], or null when the
  /// widget is built outside one (defensive for tests/edge contexts).
  static AppState? maybeOf(BuildContext context) {
    // `dependOnInheritedWidgetOfExactType` throws when no scope is present;
    // generic type lookup (`getElementForInheritedWidgetOfExactType`) lets us
    // answer null instead, so screens can degrade gracefully.
    final element = context
        .getElementForInheritedWidgetOfExactType<AppStateScope>();
    if (element == null) return null;
    return (element.widget as AppStateScope).state;
  }
}
