import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette - Light Theme
  static const Color background = Color(0xFFF5F6F8); // Light grey
  static const Color surface = Color(0xFFFFFFFF);    // Pure White
  static const Color surfaceLight = Color(0xFFE8DDB4); // Soft Background Accent
  static const Color cardBorderLight = Color(0xFFE5E5EA); // Subtle border
  
  static const Color accent = Color(0xFF285A48);      // Primary Accent (Forest Green)
  static const Color primary = accent;                // Primary Accent Alias
  static const Color accentLight = Color(0xFF3A755D); // Lighter Green
  static const Color secondary = Color(0xFFDAA464);   // Secondary Accent (Bronze/Gold)
  static const Color highlight = Color(0xFFDEC384);   // Highlight Gold
  
  // Text Colors (Light)
  static const Color textPrimary = Color(0xFF222831);   // Deep Charcoal
  static const Color textSecondary = Color(0xFF285A48); // Primary Green
  static const Color textTertiary = Color(0xFF948979);  // Neutral Taupe

  // Status Colors (Muted, premium)
  static const Color success = Color(0xFF285A48); // Primary Green
  static const Color error = Color(0xFFA35C5C);   // Muted Clay Red
  static const Color warning = Color(0xFFDAA464); // Gold
  static const Color info = Color(0xFF948979);    // Taupe

  // Dark Theme Palette
  static const Color backgroundDark = Color(0xFF1C1C1E); // Softer Muted Background
  static const Color surfaceDark = Color(0xFF2C2C2E);    // Softer Surface
  static const Color surfaceLightDark = Color(0xFF3A3A3C); // Lighter muted surface
  static const Color cardBorderDark = Color(0xFF3A3A3C);  // Dark card border
  
  static const Color textPrimaryDark = Color(0xFFE5E5EA); // Softer White
  static const Color textSecondaryDark = Color(0xFFD4C8B5); // Muted Warm Highlight
  static const Color textTertiaryDark = Color(0xFF8E8E93);  // Muted Neutral

  // Brand Identity Tokens
  static const Color brandBackground = Color(0xFF021711); // Deep Forest Emerald
  static const Color brandPrimary = Color(0xFF13A383);    // Radiant Mint Emerald
  static const Color brandPrimaryDark = Color(0xFF063628);// Deep Brand Emerald
  static const Color brandGold = Color(0xFFDAA464);       // Warm Brand Gold
  static const Color brandGoldLight = Color(0xFFFFDF73);  // Specular Gold Highlight

  // Gradients (Avoid overly colorful gradients - keep them subtle and flat-like)
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF13A383), Color(0xFF063628)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFDF73), Color(0xFFDAA464), Color(0xFF8A6327)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF285A48), Color(0xFF1E4235)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)], // Flat white for light mode
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient surfaceGradientDark = LinearGradient(
    colors: [Color(0xFF2C2C2E), Color(0xFF2C2C2E)], // Flat muted surface for dark mode
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient skyGradient = LinearGradient(
    colors: [Color(0xFFE8DDB4), Color(0xFFDEC384)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    colors: [Color(0xFF285A48), Color(0xFF1E4235)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
