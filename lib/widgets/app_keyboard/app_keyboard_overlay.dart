import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_keyboard_controller.dart';
import 'app_keyboard_types.dart';
import 'app_keyboard_view.dart';

/// Wraps the entire app in MaterialApp.builder to display the custom in-app keyboard.
/// It dynamically updates MediaQuery.viewInsets.bottom so all Scaffolds and
/// SingleScrollViews in the app automatically adjust upward when the keyboard opens!
class AppKeyboardOverlay extends StatefulWidget {
  final Widget child;

  const AppKeyboardOverlay({super.key, required this.child});

  @override
  State<AppKeyboardOverlay> createState() => _AppKeyboardOverlayState();
}

class _AppKeyboardOverlayState extends State<AppKeyboardOverlay> with WidgetsBindingObserver {
  final AppKeyboardController _controller = AppKeyboardController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onKeyboardChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onKeyboardChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onKeyboardChanged() {
    if (_controller.isVisible) {
      // Re-register to ensure we remain at the end of the observer list,
      // guaranteeing we are the very first observer to intercept didPopRoute().
      WidgetsBinding.instance.removeObserver(this);
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (_controller.isVisible) {
      _controller.hide();
      return true; // Consumes the Android back button to dismiss the keyboard instead of popping the screen!
    }
    return false;
  }

  // Approximate height of the keyboard based on mode
  double _getKeyboardHeight(AppKeyboardMode mode) {
    // Toolbar (48) + padding (16) + rows + margins
    switch (mode) {
      case AppKeyboardMode.numeric:
        return 340.0; // 4 rows of 62px + toolbar + margins
      case AppKeyboardMode.qwerty:
      case AppKeyboardMode.symbols:
        return 315.0; // 4 rows of 54px + toolbar + margins
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isVisible = _controller.isVisible;
        final keyboardHeight = isVisible ? _getKeyboardHeight(_controller.currentMode) : 0.0;
        final currentMedia = MediaQuery.of(context);

        // Adjust viewInsets so Scaffolds resize and avoid the custom keyboard
        final adjustedMedia = currentMedia.copyWith(
          viewInsets: currentMedia.viewInsets.copyWith(
            bottom: isVisible ? keyboardHeight + currentMedia.padding.bottom : currentMedia.viewInsets.bottom,
          ),
        );

        return Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && _controller.isVisible) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                _controller.hide();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: MediaQuery(
            data: adjustedMedia,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Main Application Content
                widget.child,

                // Animated In-App Keyboard
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    offset: isVisible ? Offset.zero : const Offset(0, 1.0),
                    child: const Material(
                      type: MaterialType.transparency,
                      child: AppKeyboardView(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
