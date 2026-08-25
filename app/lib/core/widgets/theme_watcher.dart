import 'package:flutter/material.dart';

/// Forces [builder] to rebuild whenever the app theme changes.
///
/// MATRIX widgets read colors from the static `AppColors` tokens (resolved
/// against the active palette at build time) instead of `Theme.of(context)`.
/// Static reads register NO inherited dependency, and Flutter's route layer
/// caches the pageBuilder result — so without this widget a theme switch
/// rebuilt the MaterialApp but left every route/sheet showing the OLD
/// palette until the app was restarted.
///
/// [ThemeWatcher] registers a real dependency on the inherited [Theme] and
/// re-invokes [builder] (producing FRESH widget instances, so the
/// identical-instance rebuild short-circuit can't skip the repaint) whenever
/// the theme changes. Wrap route pages and bottom-sheet roots with it.
class ThemeWatcher extends StatelessWidget {
  const ThemeWatcher({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    // Register the dependency: any ThemeData change (mode switch or system
    // brightness flip) marks this element dirty for the same frame.
    Theme.of(context);
    return builder(context);
  }
}
