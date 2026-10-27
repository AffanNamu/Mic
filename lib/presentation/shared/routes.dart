import 'package:flutter/material.dart';

/// A route for a full-screen step that changes data behind it while nothing
/// else is watching that data (the voice recorder: after it closes, the voice
/// list is refreshed).
///
/// It is not `opaque`. Riverpod pauses the listeners of any screen that is
/// covered by an opaque route, and when that screen reappears a provider that
/// changed in the meantime (for example the voice list after a voice was added
/// on a screen above it) rebuilds *during* the build phase, which Flutter
/// rejects in debug builds. Keeping the screens underneath alive avoids that.
/// Every screen paints its own opaque background, so nothing looks different.
///
/// Use it sparingly: with the screens underneath still on stage, a SnackBar is
/// drawn once per stacked Scaffold, so ordinary screens keep the default
/// opaque `MaterialPageRoute`.
///
/// (`MaterialPageRoute` cannot be used for this: it asserts that it is opaque.)
class DeenPageRoute<T> extends PageRouteBuilder<T> {
  DeenPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
