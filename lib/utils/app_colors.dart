import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette - Light Theme
  static const Color background = Color(0xFFF5F6F8); // Light grey
  static const Color surface = Color(0xFFFFFFFF);    // Pure White
  static const Color surfaceLight = Color(0xFFE8DDB4); // Soft Background Accent
  
  static const Color accent = Color(0xFF285A48);      // Primary Accent (Forest Green)
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
  static const Color backgroundDark = Color(0xFF222831); // Primary Background (Deep Charcoal)
  static const Color surfaceDark = Color(0xFF393E46);    // Secondary Surface (Charcoal Grey)
  static const Color surfaceLightDark = Color(0xFF4A5058); // Slightly lighter surface
  
  static const Color textPrimaryDark = Color(0xFFF8F9FA); // Off White
  static const Color textSecondaryDark = Color(0xFFDFD0B8); // Warm Highlight
  static const Color textTertiaryDark = Color(0xFF948979);  // Neutral Accent

  // Gradients (Avoid overly colorful gradients - keep them subtle and flat-like)
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
    colors: [Color(0xFF393E46), Color(0xFF393E46)], // Flat charcoal for dark mode
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient skyGradient = LinearGradient(
    colors: [Color(0xFFE8DDB4), Color(0xFFDEC384)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

