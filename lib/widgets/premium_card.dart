import 'package:flutter/material.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;
  final Border? border;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.boxShadow,
    this.gradient,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? cardTheme.color ?? theme.colorScheme.surface,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius ?? 24),
        border: border ?? (cardTheme.shape is RoundedRectangleBorder 
          ? ((cardTheme.shape as RoundedRectangleBorder).side != BorderSide.none 
            ? Border.fromBorderSide((cardTheme.shape as RoundedRectangleBorder).side)
            : Border.all(color: theme.colorScheme.outline.withOpacity( 0.1), width: 1))
          : null),
        boxShadow: boxShadow ?? (isDark ? null : [
          BoxShadow(
            color: theme.shadowColor.withOpacity( 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ]),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius ?? 24),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

