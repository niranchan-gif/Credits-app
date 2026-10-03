import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// High-performance static glass background.
/// Provides rich ambient glow using hardware-accelerated radial gradients
/// without CPU/GPU animation loops or costly full-screen ImageFiltered blur overhead.
class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1714) : const Color(0xFFE8F0EA);

    return Stack(
      children: [
        // Base solid color
        Positioned.fill(
          child: ColoredBox(color: bgColor),
        ),

        // Top Right Ambient Orb (Primary Accent)
        Positioned(
          top: -60,
          right: -60,
          width: 360,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPrimary.withValues(alpha: isDark ? 0.28 : 0.32),
                    AppColors.brandPrimary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Left Ambient Orb (Secondary Gold Accent)
        Positioned(
          bottom: -50,
          left: -80,
          width: 380,
          height: 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandGold.withValues(alpha: isDark ? 0.20 : 0.25),
                    AppColors.brandGold.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Center Subtle Emerald Orb
        Positioned(
          top: 260,
          left: 40,
          width: 280,
          height: 280,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? const Color(0xFF063628) : const Color(0xFF6EDDBB))
                        .withValues(alpha: isDark ? 0.24 : 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // App content
        Positioned.fill(child: child),
      ],
    );
  }
}

