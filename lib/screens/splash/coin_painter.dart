import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paints the realistic metallic PBR coin faces (Side A & Side B) and milled rim layers.
class CoinFacePainter extends CustomPainter {
  final bool isSideA;
  final double reflectionAngle;
  final bool isDarkTheme;

  CoinFacePainter({
    required this.isSideA,
    required this.reflectionAngle,
    required this.isDarkTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // 1. Outer Shadow & Rim Bevel
    final outerRimRect = Rect.fromCircle(center: center, radius: radius);
    final rimGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      colors: const [
        Color(0xFFFFE893),
        Color(0xFFD4AF37),
        Color(0xFF8B6508),
        Color(0xFFF9D976),
        Color(0xFF9A6D22),
        Color(0xFFFFE893),
      ],
      stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      transform: GradientRotation(reflectionAngle * 0.5),
    );

    final rimPaint = Paint()
      ..shader = rimGradient.createShader(outerRimRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, rimPaint);

    // 2. Inner Debossed Ring (Bevel effect)
    final bevelRadius = radius * 0.92;
    final bevelRect = Rect.fromCircle(center: center, radius: bevelRadius);
    const bevelGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF7A5806),
        Color(0xFFE9B646),
        Color(0xFFFFF1B0),
        Color(0xFF8B6508),
      ],
      stops: [0.0, 0.3, 0.7, 1.0],
    );
    final bevelPaint = Paint()
      ..shader = bevelGradient.createShader(bevelRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.035;
    canvas.drawCircle(center, bevelRadius, bevelPaint);

    // 3. Main Metallic Brushed Face Disc
    final faceRadius = radius * 0.88;
    final faceRect = Rect.fromCircle(center: center, radius: faceRadius);
    const faceGradient = RadialGradient(
      center: Alignment(-0.2, -0.2),
      radius: 1.1,
      colors: [
        Color(0xFFFFF7D6),
        Color(0xFFF0C45C),
        Color(0xFFD4AF37),
        Color(0xFFA87918),
        Color(0xFF7A5806),
      ],
      stops: [0.0, 0.3, 0.6, 0.85, 1.0],
    );
    final facePaint = Paint()
      ..shader = faceGradient.createShader(faceRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, faceRadius, facePaint);

    // 4. Brushed Metal Texture (Subtle concentric micro-grooves)
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF5A3E04).withValues(alpha: 0.12);
    for (int i = 1; i <= 8; i++) {
      canvas.drawCircle(center, faceRadius * (i / 9.0), groovePaint..strokeWidth = 0.6);
    }

    // 5. Dynamic PBR Reflection Highlight (Shifts with coin spin)
    final reflectionRect = Rect.fromCircle(center: center, radius: faceRadius);
    final pbrGradient = LinearGradient(
      begin: Alignment(math.cos(reflectionAngle), math.sin(reflectionAngle)),
      end: Alignment(-math.cos(reflectionAngle), -math.sin(reflectionAngle)),
      colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.35),
        const Color(0xFFFFF1B0).withValues(alpha: 0.2),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.3, 0.48, 0.52, 0.7],
    );
    final pbrPaint = Paint()
      ..shader = pbrGradient.createShader(reflectionRect)
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(center, faceRadius, pbrPaint);

    // 6. Side A: Center Engraved Currency Symbol | Side B: Subtle inner decorative border
    if (isSideA) {
      _drawEngravedRupee(canvas, center, faceRadius);
    } else {
      final logoBorderRadius = faceRadius * 0.75;
      final logoBorderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF9A6D22).withValues(alpha: 0.6);
      canvas.drawCircle(center, logoBorderRadius, logoBorderPaint);
    }
  }

  void _drawEngravedRupee(Canvas canvas, Offset center, double radius) {
    final textStyle = TextStyle(
      fontSize: radius * 0.95,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF7A5806),
    );

    final textSpan = TextSpan(text: '₹', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );

    // Debossed bottom-right shadow (creates engraved depth)
    final shadowSpan = TextSpan(
      text: '₹',
      style: textStyle.copyWith(color: const Color(0xFFFFF9E6).withValues(alpha: 0.85)),
    );
    final shadowPainter = TextPainter(
      text: shadowSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    shadowPainter.layout();
    shadowPainter.paint(canvas, textOffset + const Offset(1.5, 1.5));

    // Dark inner groove
    final darkSpan = TextSpan(
      text: '₹',
      style: textStyle.copyWith(color: const Color(0xFF4A3202)),
    );
    final darkPainter = TextPainter(
      text: darkSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    darkPainter.layout();
    darkPainter.paint(canvas, textOffset);

    // Gold fill
    final fillSpan = TextSpan(
      text: '₹',
      style: textStyle.copyWith(
        foreground: Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9B646), Color(0xFF9A6D22)],
          ).createShader(Rect.fromLTWH(textOffset.dx, textOffset.dy, textPainter.width, textPainter.height)),
      ),
    );
    final fillPainter = TextPainter(
      text: fillSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    fillPainter.layout();
    fillPainter.paint(canvas, textOffset + const Offset(0.5, 0.5));
  }


  @override
  bool shouldRepaint(covariant CoinFacePainter oldDelegate) {
    return oldDelegate.reflectionAngle != reflectionAngle ||
           oldDelegate.isSideA != isSideA ||
           oldDelegate.isDarkTheme != isDarkTheme;
  }
}

/// Paints an extruded milled rim slice for realistic 3D depth during spin.
class CoinRimPainter extends CustomPainter {
  final double reflectionAngle;

  CoinRimPainter({required this.reflectionAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final rimRect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      colors: const [
        Color(0xFF8B6508),
        Color(0xFFD4AF37),
        Color(0xFF5A3E04),
        Color(0xFFF9D976),
        Color(0xFF8B6508),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(reflectionAngle),
    );

    final paint = Paint()
      ..shader = gradient.createShader(rimRect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);

    // Outer dark serration ring
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF3A2802).withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CoinRimPainter oldDelegate) {
    return oldDelegate.reflectionAngle != reflectionAngle;
  }
}
