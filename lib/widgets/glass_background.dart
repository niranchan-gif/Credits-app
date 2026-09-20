import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class GlassBackground extends StatefulWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Background base color
    final bgColor = isDark ? const Color(0xFF0F1714) : const Color(0xFFE8F0EA);
    
    return Stack(
      children: [
        // Base solid color
        Container(color: bgColor),
        
        // Animated Orbs with ImageFiltered instead of BackdropFilter
        // This avoids nested BackdropFilter rendering glitches in Impeller
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80, tileMode: TileMode.decal),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                final width = MediaQuery.of(context).size.width;
                final height = MediaQuery.of(context).size.height;
                
                return Stack(
                  children: [
                    // Top Right Orb (Primary Accent)
                    Positioned(
                      top: height * 0.1 + sin(t * pi * 2) * 50,
                      right: width * -0.2 + cos(t * pi * 2) * 50,
                      child: Container(
                        width: width * 0.8,
                        height: width * 0.8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandPrimary.withValues(alpha: isDark ? 0.3 : 0.4),
                        ),
                      ),
                    ),
                    
                    // Bottom Left Orb (Secondary Accent)
                    Positioned(
                      bottom: height * 0.05 + cos(t * pi * 2) * 60,
                      left: width * -0.3 + sin(t * pi * 2) * 40,
                      child: Container(
                        width: width * 0.9,
                        height: width * 0.9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandGold.withValues(alpha: isDark ? 0.25 : 0.35),
                        ),
                      ),
                    ),
                    
                    // Center Subtle Orb (Deep Blue/Teal)
                    Positioned(
                      top: height * 0.4 + sin(t * pi * 4) * 30,
                      left: width * 0.2 + cos(t * pi * 4) * 30,
                      child: Container(
                        width: width * 0.6,
                        height: width * 0.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isDark ? const Color(0xFF063628) : const Color(0xFF6EDDBB)).withValues(alpha: isDark ? 0.4 : 0.5),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        
        // Actual content
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
