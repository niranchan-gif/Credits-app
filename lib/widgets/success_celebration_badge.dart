import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A sleek, background-integrated checkmark badge with dynamic path-traced check stroke,
/// perimeter ring animation, soft ambient radiance, and shockwave ripple.
/// Merges seamlessly into the dialog or screen background without an opaque disc.
class SuccessCelebrationBadge extends StatefulWidget {
  final double size;
  final Color? color;
  final VoidCallback? onComplete;

  const SuccessCelebrationBadge({
    super.key,
    this.size = 110.0,
    this.color,
    this.onComplete,
  });

  @override
  State<SuccessCelebrationBadge> createState() => _SuccessCelebrationBadgeState();
}

class _SuccessCelebrationBadgeState extends State<SuccessCelebrationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _ringDrawAnimation;
  late Animation<double> _checkDrawAnimation;
  late Animation<double> _punchAnimation;
  late Animation<double> _rippleAnimation;
  late Animation<double> _glowAnimation;
  bool _hasTriggeredHaptic = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // 1. Initial subtle entrance scale (0.0 to 0.35)
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
      ),
    );

    // 2. Perimeter ring stroke sweeps 360 degrees (0.05 to 0.50)
    _ringDrawAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.50, curve: Curves.easeInOutCubic),
    );

    // 3. Dynamic Checkmark Path Tracing (0.35 to 0.72)
    _checkDrawAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.72, curve: Curves.easeOutCubic),
    );

    // 4. Subtle punch spring right as the check completes (0.68 to 0.86)
    _punchAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 0.86),
    ));

    // 5. Outer shockwave ripple expanding into the background (0.68 to 0.98)
    _rippleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 0.98, curve: Curves.easeOutCubic),
    );

    // 6. Ambient soft glow pulse (0.20 to 0.75)
    _glowAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.20, 0.75, curve: Curves.easeOutQuad),
    );

    _controller.addListener(_onAnimationUpdate);

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  void _onAnimationUpdate() {
    // Satisfying haptic feedback right when the check stroke finishes
    if (_controller.value >= 0.70 && !_hasTriggeredHaptic) {
      _hasTriggeredHaptic = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = widget.color ??
        (isDark ? const Color(0xFF34D399) : const Color(0xFF10B981));

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final effectiveScale = _controller.value < 0.68
              ? _scaleAnimation.value
              : _punchAnimation.value;

          return CustomPaint(
            painter: _MergedCelebrationPainter(
              color: themeColor,
              isDark: isDark,
              scale: effectiveScale,
              ringDrawProgress: _ringDrawAnimation.value,
              checkDrawProgress: _checkDrawAnimation.value,
              rippleProgress: _rippleAnimation.value,
              glowProgress: _glowAnimation.value,
            ),
          );
        },
      ),
    );
  }
}

class _MergedCelebrationPainter extends CustomPainter {
  final Color color;
  final bool isDark;
  final double scale;
  final double ringDrawProgress;
  final double checkDrawProgress;
  final double rippleProgress;
  final double glowProgress;

  _MergedCelebrationPainter({
    required this.color,
    required this.isDark,
    required this.scale,
    required this.ringDrawProgress,
    required this.checkDrawProgress,
    required this.rippleProgress,
    required this.glowProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = (size.width * 0.38) * scale;
    final outerGlowRadius = size.width * 0.48;

    // 1. Draw soft ambient glow that melts into the background
    if (glowProgress > 0.01) {
      final ambientGlowPaint = Paint()
        ..color = color.withValues(alpha: (isDark ? 0.12 : 0.08) * glowProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18.0);
      canvas.drawCircle(center, ringRadius * 1.05, ambientGlowPaint);

      // Subtle soft translucent inner wash that merges into background
      final washPaint = Paint()
        ..color = color.withValues(alpha: (isDark ? 0.08 : 0.05) * glowProgress)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, ringRadius, washPaint);
    }

    // 2. Draw shockwave ripple expanding outward into the background
    if (rippleProgress > 0.01 && rippleProgress < 0.99) {
      final currentRippleRadius =
          ringRadius + (outerGlowRadius - ringRadius) * rippleProgress;
      final rippleAlpha = (1.0 - rippleProgress).clamp(0.0, 1.0);
      final ripplePaint = Paint()
        ..color = color.withValues(alpha: rippleAlpha * (isDark ? 0.40 : 0.30))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 * rippleAlpha).clamp(0.5, 2.2);
      canvas.drawCircle(center, currentRippleRadius, ripplePaint);
    }

    // 3. Draw circular perimeter track (subtle background guide)
    final trackPaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.16 : 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.038).clamp(2.5, 4.0);
    canvas.drawCircle(center, ringRadius, trackPaint);

    // 4. Draw active animated perimeter ring stroke sweeping 360 degrees
    if (ringDrawProgress > 0.005) {
      final ringStrokeWidth = (size.width * 0.042).clamp(3.0, 4.5);
      final ringPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStrokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // Start from 12 o'clock
      final sweepAngle = 2 * math.pi * ringDrawProgress.clamp(0.0, 1.0);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        startAngle,
        sweepAngle,
        false,
        ringPaint,
      );
    }

    // 5. Draw dynamically path-traced checkmark in theme color
    if (checkDrawProgress > 0.005) {
      final checkStrokeWidth = (size.width * 0.068).clamp(4.0, 6.5);

      final checkPath = Path();
      final r = ringRadius;

      // Perfectly balanced checkmark coordinates centered inside the ring
      final start = center + Offset(-r * 0.44, -r * 0.02);
      final vertex = center + Offset(-r * 0.10, r * 0.34);
      final end = center + Offset(r * 0.48, -r * 0.32);

      checkPath.moveTo(start.dx, start.dy);
      checkPath.lineTo(vertex.dx, vertex.dy);
      checkPath.lineTo(end.dx, end.dy);

      // Extract path up to current animated length
      final metrics = checkPath.computeMetrics();
      for (final metric in metrics) {
        final extractLength =
            metric.length * checkDrawProgress.clamp(0.0, 1.0);
        final extracted = metric.extractPath(0.0, extractLength);

        // Soft subtle glow underneath check stroke
        final glowPaint = Paint()
          ..color = color.withValues(alpha: (isDark ? 0.35 : 0.22))
          ..style = PaintingStyle.stroke
          ..strokeWidth = checkStrokeWidth + 3.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawPath(extracted, glowPaint);

        // Crisp foreground check stroke
        final checkPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = checkStrokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(extracted, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MergedCelebrationPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isDark != isDark ||
        oldDelegate.scale != scale ||
        oldDelegate.ringDrawProgress != ringDrawProgress ||
        oldDelegate.checkDrawProgress != checkDrawProgress ||
        oldDelegate.rippleProgress != rippleProgress ||
        oldDelegate.glowProgress != glowProgress;
  }
}
