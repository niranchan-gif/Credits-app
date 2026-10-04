import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/glass_background.dart';

/// A custom page transitions builder tailored specifically for glassmorphic
/// and transparent scaffold architectures.
///
/// Prevents the common "see-through ghosting glitch" where transparent routes
/// collide and overlap during route animations. Wraps the route with [GlassBackground]
/// to present a solid, beautifully ambient canvas during transition, with
/// hardware-accelerated slide and fade curves.
class SmoothGlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothGlassPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SmoothGlassTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _SmoothGlassTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _SmoothGlassTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    // Primary curve: when this route is pushed or popped
    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Secondary curve: when a subsequent route is pushed on top of this route
    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // On Desktop, a refined 6% slide + fade is standard and avoids wide sweep jank
    // On Mobile, a smooth 100% horizontal slide with soft left shadow feels native
    final primarySlideTween = isDesktop
        ? Tween<Offset>(begin: const Offset(0.06, 0.0), end: Offset.zero)
        : Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero);

    final primaryFadeTween = isDesktop
        ? Tween<double>(begin: 0.0, end: 1.0)
        : Tween<double>(begin: 0.85, end: 1.0);

    // Secondary motion: route behind slightly shifts left and dims
    final secondarySlideTween = isDesktop
        ? Tween<Offset>(begin: Offset.zero, end: const Offset(-0.02, 0.0))
        : Tween<Offset>(begin: Offset.zero, end: const Offset(-0.25, 0.0));

    final secondaryFadeTween = Tween<double>(begin: 1.0, end: 0.88);

    // Provide the solid ambient GlassBackground so underlying routes NEVER ghost through!
    Widget wrappedChild = RepaintBoundary(
      child: GlassBackground(
        child: child,
      ),
    );

    // Add soft left elevation shadow on mobile
    if (!isDesktop) {
      wrappedChild = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(-4, 0),
            ),
          ],
        ),
        child: wrappedChild,
      );
    }

    // Apply primary entrance/exit transition
    Widget current = SlideTransition(
      position: primarySlideTween.animate(primaryCurve),
      child: FadeTransition(
        opacity: primaryFadeTween.animate(primaryCurve),
        child: wrappedChild,
      ),
    );

    // Apply secondary transition (when another screen is pushed on top)
    return SlideTransition(
      position: secondarySlideTween.animate(secondaryCurve),
      child: FadeTransition(
        opacity: secondaryFadeTween.animate(secondaryCurve),
        child: current,
      ),
    );
  }
}
