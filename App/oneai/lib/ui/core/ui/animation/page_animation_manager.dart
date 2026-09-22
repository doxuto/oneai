import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

/// Manages page transition animations for navigation
class PageAnimationManager {
  /// Creates a fade transition
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: CurveTween(curve: Curves.easeInOut).animate(animation), child: child);

  /// Creates a slide transition from right to left
  static Widget slideRightToLeftTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(animation),
    child: child,
  );

  /// Creates a slide transition from bottom to top
  static Widget slideBottomToTopTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
    child: child,
  );

  /// Creates a scale transition
  static Widget scaleTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => ScaleTransition(scale: CurveTween(curve: Curves.easeInOut).animate(animation), child: child);

  /// Creates a custom page with the specified transition
  static Page<void> createPage({
    required LocalKey key,
    required Widget child,
    required Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    )
    transitionBuilder,
  }) =>
      Platform.isIOS || Platform.isMacOS
          // Use CupertinoPage for iOS and macOS to support swipe back gesture
          // and consistent iOS navigation style
          // Use CustomTransitionPage for other platforms to allow custom transitions
          ? CupertinoPage(key: key, child: child)
          : CustomTransitionPage(key: key, child: child, transitionsBuilder: transitionBuilder);
}
