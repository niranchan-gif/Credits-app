import 'package:flutter/material.dart';

/// A buttery-smooth animated replacement for [IndexedStack].
///
/// Preserves the state of all children (scroll positions, form inputs, caches)
/// via [maintainState: true], while providing a rich, glitch-free Material 3
/// fade-through and subtle elevation slide transition between screens.
class SmoothAnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const SmoothAnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<SmoothAnimatedIndexedStack> createState() => _SmoothAnimatedIndexedStackState();
}

class _SmoothAnimatedIndexedStackState extends State<SmoothAnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _previousIndex = null;
          });
        }
      });
  }

  @override
  void didUpdateWidget(SmoothAnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _currentIndex) {
      _previousIndex = _currentIndex;
      _currentIndex = widget.index;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animValue = _controller.value;
        final isAnimating = _controller.isAnimating && _previousIndex != null;

        // Outgoing screen fade-out (0.0 -> 0.4 interval)
        final outgoingOpacity = isAnimating
            ? (1.0 - (animValue / 0.4).clamp(0.0, 1.0))
            : 0.0;

        // Incoming screen fade-in (0.2 -> 1.0 interval)
        final incomingT = ((animValue - 0.2) / 0.8).clamp(0.0, 1.0);
        final incomingCurve = Curves.easeOutCubic.transform(incomingT);
        final incomingOpacity = isAnimating ? incomingCurve : 1.0;
        final incomingOffsetY = isAnimating ? 10.0 * (1.0 - incomingCurve) : 0.0;
        final incomingScale = isAnimating ? 0.985 + (0.015 * incomingCurve) : 1.0;

        return Stack(
          fit: StackFit.expand,
          children: List.generate(widget.children.length, (i) {
            final isCurrent = i == _currentIndex;
            final isPrevious = i == _previousIndex;

            if (!isCurrent && !isPrevious) {
              return TickerMode(
                enabled: false,
                child: Offstage(
                  offstage: true,
                  child: RepaintBoundary(child: widget.children[i]),
                ),
              );
            }

            if (isPrevious && isAnimating) {
              return TickerMode(
                enabled: false,
                child: Offstage(
                  offstage: false,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: true,
                      child: Opacity(
                        opacity: outgoingOpacity,
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
              );
            }

            // Current visible/entering child
            return TickerMode(
              enabled: true,
              child: Offstage(
                offstage: false,
                child: RepaintBoundary(
                  child: IgnorePointer(
                    ignoring: isAnimating && incomingOpacity < 0.5,
                    child: Opacity(
                      opacity: incomingOpacity,
                      child: Transform.translate(
                        offset: Offset(0, incomingOffsetY),
                        child: Transform.scale(
                          scale: incomingScale,
                          child: widget.children[i],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
