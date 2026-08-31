import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  /// A premium, slightly elevated card decoration with subtle shadow and border.
  static BoxDecoration premiumCard(bool isDark) {
    return BoxDecoration(
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Soft shadow for list items that elevate slightly
  static BoxDecoration subtleShadowCard(bool isDark) {
    return BoxDecoration(
      color: isDark ? AppColors.surfaceLightDark : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
