import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  /// A premium, slightly elevated card decoration with dual-layer diffuse ambient shadow and micro-border.
  static BoxDecoration premiumCard(bool isDark) {
    return BoxDecoration(
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        width: 1,
      ),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  /// Soft shadow for list items and cards that elevate gently
  static BoxDecoration subtleShadowCard(bool isDark) {
    return BoxDecoration(
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        width: 1,
      ),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  /// Hero card with subtle specular border and rich ambient glow
  static BoxDecoration heroCard(bool isDark) {
    return BoxDecoration(
      gradient: AppColors.heroCardGradient,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.18),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: isDark ? 0.35 : 0.25),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

