import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive Space Header with an animated Rocket that matches the Credits brand theme
/// and flies away with realistic fire, ash, and smoke particles upon download completion.
class RocketUpdateHeader extends StatefulWidget {
  final bool isDownloading;
  final double downloadProgress;
  final bool isLaunching;
  final bool isDark;
  final VoidCallback? onLaunchComplete;

  const RocketUpdateHeader({
    super.key,
    required this.isDownloading,
    required this.downloadProgress,
    required this.isLaunching,
    this.isDark = true,
    this.onLaunchComplete,
  });

  /// Computes the exact center coordinate of the rocket on screen for both drawing and particle emission
  static Offset computeRocketCenter({
    required double progress,
    required double cardWidth,
    required double cardHeight,
  }) {
    const double baseFlightAngle = -math.pi / 4;
    double posX = cardWidth * 0.48;
    double posY = cardHeight * 0.54;

    if (progress <= 0.001) {
      return Offset(posX, posY);
    }

    if (progress <= 0.18) {
      // Phase 1: Pad Ignition & Rumble (rocket rumbles on pad, net displacement is 0)
      final double jitterFactor = 1.0 - (progress / 0.18);
      final double jitter = math.sin(progress * 160.0) * (3.0 * jitterFactor);
      return Offset(posX + jitter, posY - jitter * 0.5);
    }

    // Phase 2: Liftoff & Acceleration (rocket leads into the sky, smoothly accelerating)
    final double tFlight = ((progress - 0.18) / 0.82).clamp(0.0, 1.0);
    final double curvedFlight = Curves.easeInCubic.transform(tFlight);
    final double flightDistance = curvedFlight * 780.0;

    posX += flightDistance * math.cos(baseFlightAngle);
    posY += flightDistance * math.sin(baseFlightAngle);

    if (tFlight < 0.25) {
      final double rumble = math.sin(tFlight * 80.0) * (1.8 * (1.0 - tFlight * 4.0));
      posX += rumble;
      posY += rumble;
    }

    return Offset(posX, posY);
  }

  /// Computes the exact position of the rear exhaust nozzle (strictly behind the rocket nose)
  static Offset computeNozzlePosition(Offset rocketCenter) {
    const double baseFlightAngle = -math.pi / 4;
    // Fuselage nozzle is 48px behind center along opposite flight direction
    return Offset(
      rocketCenter.dx - math.cos(baseFlightAngle) * 48.0,
      rocketCenter.dy - math.sin(baseFlightAngle) * 48.0,
    );
  }

  @override
  State<RocketUpdateHeader> createState() => _RocketUpdateHeaderState();
}

class _RocketUpdateHeaderState extends State<RocketUpdateHeader> with TickerProviderStateMixin {
  // Idle floating animation controller (gentle hover & flame shimmer)
  late AnimationController _hoverController;

  // Continuous fluid time controller for natural unidirectional smoke flow & rolling billows
  late AnimationController _smokeController;

  // Rocket launch & blastoff animation controller
  late AnimationController _blastController;

  bool _hasTriggeredCompletion = false;

  @override
  void initState() {
    super.initState();

    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _smokeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _blastController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _blastController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_hasTriggeredCompletion) {
        _hasTriggeredCompletion = true;
        widget.onLaunchComplete?.call();
      }
    });

    if (widget.isLaunching) {
      _startLaunch();
    }
  }

  @override
  void didUpdateWidget(covariant RocketUpdateHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLaunching && !oldWidget.isLaunching) {
      _startLaunch();
    }
  }

  void _startLaunch() {
    _hasTriggeredCompletion = false;
    _blastController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _smokeController.dispose();
    _blastController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230.0,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: widget.isDark
            ? const RadialGradient(
                center: Alignment(0.2, -0.3),
                radius: 1.4,
                colors: [
                  Color(0xFF09362A), // Deep Emerald Space Core
                  Color(0xFF041B15), // Mid Space Night
                  Color(0xFF02130E), // Outer Edge Deep Obsidian
                ],
                stops: [0.0, 0.6, 1.0],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8F6F1), // Crisp mint light dawn
                  Color(0xFFD3EFE3), // Soft jade morning sky
                  Color(0xFFBEE7D5), // Fresh light emerald tint
                ],
              ),
        border: Border.all(
          color: widget.isDark
              ? const Color(0xFF13A383).withValues(alpha: 0.3)
              : const Color(0xFF13A383).withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isDark
                ? const Color(0xFF13A383).withValues(alpha: 0.12)
                : const Color(0xFF0B6D55).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          if (widget.isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedBuilder(
          animation: Listenable.merge([_hoverController, _smokeController, _blastController]),
          builder: (context, _) {
            return CustomPaint(
              painter: _RocketSpacePainter(
                hoverValue: _hoverController.value,
                smokeValue: _smokeController.value,
                blastValue: _blastController.value,
                isDownloading: widget.isDownloading,
                downloadProgress: widget.downloadProgress,
                isDark: widget.isDark,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _RocketSpacePainter extends CustomPainter {
  final double hoverValue;
  final double smokeValue;
  final double blastValue;
  final bool isDownloading;
  final double downloadProgress;
  final bool isDark;

  _RocketSpacePainter({
    required this.hoverValue,
    required this.smokeValue,
    required this.blastValue,
    required this.isDownloading,
    required this.downloadProgress,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSpaceBackdrop(canvas, size);
    _drawLaunchPadSmoke(canvas, size);
    _drawIdleThrusterWisps(canvas, size);
    _drawFlightExhaustSmoke(canvas, size);
    _drawRocket(canvas, size);
  }

  void _drawSpaceBackdrop(Canvas canvas, Size size) {
    // A. Celestial Body (Upper-Right): Crescent Moon in dark mode, Radiant Sun in light mode
    final double moonCenterX = size.width * 0.78;
    final double moonCenterY = size.height * 0.32;
    const double moonRadius = 34.0;

    if (isDark) {
      final moonAuraPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFDF73).withValues(alpha: 0.22),
            const Color(0xFFDAA464).withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(moonCenterX, moonCenterY), radius: moonRadius * 2.2));
      canvas.drawCircle(Offset(moonCenterX, moonCenterY), moonRadius * 2.2, moonAuraPaint);

      final moonPath = Path()
        ..addOval(Rect.fromCircle(center: Offset(moonCenterX, moonCenterY), radius: moonRadius));
      final moonCutout = Path()
        ..addOval(Rect.fromCircle(center: Offset(moonCenterX - 13, moonCenterY - 5), radius: moonRadius * 0.88));

      final crescentPath = Path.combine(PathOperation.difference, moonPath, moonCutout);
      final moonPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF9E6),
            Color(0xFFFFE79A),
            Color(0xFFDAA464),
          ],
        ).createShader(Rect.fromCircle(center: Offset(moonCenterX, moonCenterY), radius: moonRadius));
      canvas.drawPath(crescentPath, moonPaint);
    } else {
      // Light Mode: Radiant Morning Sun
      final sunAuraPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFDF73).withValues(alpha: 0.32),
            const Color(0xFFDAA464).withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(moonCenterX, moonCenterY), radius: moonRadius * 2.2));
      canvas.drawCircle(Offset(moonCenterX, moonCenterY), moonRadius * 2.2, sunAuraPaint);

      final sunPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFBE8),
            Color(0xFFFFDF73),
            Color(0xFFEAA646),
          ],
        ).createShader(Rect.fromCircle(center: Offset(moonCenterX, moonCenterY), radius: moonRadius));
      canvas.drawCircle(Offset(moonCenterX, moonCenterY), moonRadius, sunPaint);
    }

    // B. Distant Ringed Planet (Upper-Left)
    final double planetX = size.width * 0.20;
    final double planetY = size.height * 0.26;
    const double planetRadius = 13.0;

    final planetPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: isDark
            ? const [
                Color(0xFF285A48),
                Color(0xFF0F392D),
                Color(0xFF062319),
              ]
            : const [
                Color(0xFF439A7C),
                Color(0xFF227157),
                Color(0xFF124C38),
              ],
      ).createShader(Rect.fromCircle(center: Offset(planetX, planetY), radius: planetRadius));
    canvas.drawCircle(Offset(planetX, planetY), planetRadius, planetPaint);

    canvas.save();
    canvas.translate(planetX, planetY);
    canvas.rotate(-0.35);
    final ringPaint = Paint()
      ..color = const Color(0xFFDAA464).withValues(alpha: isDark ? 0.65 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(const Rect.fromLTWH(-22, -5.5, 44, 11), ringPaint);
    canvas.restore();

    // C. Twinkling Stars / Sparkles
    const List<Offset> starOffsets = [
      Offset(0.12, 0.18),
      Offset(0.35, 0.12),
      Offset(0.48, 0.22),
      Offset(0.62, 0.14),
      Offset(0.88, 0.18),
      Offset(0.92, 0.45),
      Offset(0.15, 0.52),
      Offset(0.32, 0.42),
      Offset(0.68, 0.50),
    ];

    for (int i = 0; i < starOffsets.length; i++) {
      final norm = starOffsets[i];
      final double sx = norm.dx * size.width;
      final double sy = norm.dy * size.height;
      final double twinkle = (0.5 + 0.5 * math.sin(hoverValue * math.pi * 2 + i * 1.2)).clamp(0.2, 1.0);

      final Color starColor;
      if (isDark) {
        starColor = (i % 2 == 0 ? const Color(0xFFFFDF73) : const Color(0xFF13A383)).withValues(alpha: 0.75 * twinkle);
      } else {
        starColor = (i % 2 == 0 ? const Color(0xFFD6942B) : const Color(0xFF0F876B)).withValues(alpha: 0.70 * twinkle);
      }

      final starPaint = Paint()..color = starColor;

      if (i % 3 == 0) {
        final path = Path()
          ..moveTo(sx, sy - 4.0)
          ..quadraticBezierTo(sx, sy, sx + 4.0, sy)
          ..quadraticBezierTo(sx, sy, sx, sy + 4.0)
          ..quadraticBezierTo(sx, sy, sx - 4.0, sy)
          ..quadraticBezierTo(sx, sy, sx, sy - 4.0);
        canvas.drawPath(path, starPaint);
      } else {
        canvas.drawCircle(Offset(sx, sy), (1.0 + (i % 2) * 0.8) * twinkle, starPaint);
      }
    }
  }

  /// Draws a soft, organic volumetric vapor puff with Gaussian diffusion, eliminating hard edges
  void _drawSoftVaporPuff(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    double blurSigma = 12.0,
    double opacity = 1.0,
  }) {
    if (radius <= 0.8 || opacity <= 0.005) return;
    final double op = opacity.clamp(0.0, 1.0);

    final Paint puffPaint = Paint()
      ..color = color.withValues(alpha: (color.a * op).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.drawCircle(center, radius, puffPaint);
  }

  void _drawLaunchPadSmoke(Canvas canvas, Size size) {
    final double baseY = size.height - 4.0;
    final bool isLaunching = blastValue > 0.0;
    final double w = size.width;
    final double h = size.height;

    double surge = 0.0;
    double alphaMod = 1.0;

    if (isLaunching) {
      if (blastValue <= 0.18) {
        // Explosive pad deluge steam surge
        surge = (blastValue / 0.18);
      } else {
        final double t = ((blastValue - 0.18) / 0.82).clamp(0.0, 1.0);
        surge = 1.0 + t * 0.45;
        alphaMod = (1.0 - t * 0.60).clamp(0.12, 1.0);
      }
    } else if (isDownloading) {
      surge = 0.18 + (downloadProgress * 0.45);
    } else {
      surge = 0.12;
    }

    // 1. Radiant Thruster Deluge Backlight Glow
    // When the thrusters fire downward, hot fire reflects off the pad and backlights the steam
    if ((isLaunching && blastValue <= 0.42) || isDownloading) {
      final double glowIntensity = isLaunching
          ? (1.0 - blastValue / 0.42).clamp(0.0, 1.0)
          : (0.20 + downloadProgress * 0.50);

      final padGlowPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 0.3),
          colors: [
            const Color(0xFFFFB347).withValues(alpha: 0.60 * glowIntensity),
            const Color(0xFFFF5722).withValues(alpha: 0.38 * glowIntensity),
            const Color(0xFFDAA464).withValues(alpha: 0.14 * glowIntensity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 0.70, 1.0],
        ).createShader(Rect.fromCenter(
          center: Offset(w * 0.48, baseY - 8 - surge * 12),
          width: 250 + surge * 140,
          height: 120 + surge * 60,
        ))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.48, baseY - 8 - surge * 12),
          width: 250 + surge * 140,
          height: 120 + surge * 60,
        ),
        padGlowPaint,
      );
    }

    // 2. Continuous Deep Atmospheric Ground Fog (Gaussian blurred base blanket)
    final double fogHeight = 50.0 + surge * 30.0;
    final fogPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                Colors.transparent,
                const Color(0xFFF2FAF7).withValues(alpha: 0.15 * alphaMod),
                const Color(0xFFD6E8E2).withValues(alpha: 0.45 * alphaMod),
                const Color(0xFF384A45).withValues(alpha: 0.70 * alphaMod),
              ]
            : [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.20 * alphaMod),
                const Color(0xFFE8F4F0).withValues(alpha: 0.65 * alphaMod),
                const Color(0xFFCBE2D9).withValues(alpha: 0.85 * alphaMod),
              ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromLTWH(0, h - fogHeight, w, fogHeight))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawRect(Rect.fromLTWH(-20, h - fogHeight, w + 40, fogHeight + 20), fogPaint);

    // 3. Rolling Volumetric Steam Wave Bank (Undulating fluid vapor body, zero sharp circles)
    final pathSteamBack = Path()
      ..moveTo(-20, h + 10)
      ..lineTo(-20, baseY - 20 - surge * 22);

    final double waveT1 = smokeValue * math.pi * 2;
    pathSteamBack.cubicTo(
      w * 0.20, baseY - 35 - surge * 28 + math.sin(waveT1) * 6.0,
      w * 0.40, baseY - 16 - surge * 18 + math.cos(waveT1 * 1.3) * 5.0,
      w * 0.52, baseY - 32 - surge * 32 + math.sin(waveT1 * 1.7) * 7.0,
    );
    pathSteamBack.cubicTo(
      w * 0.68, baseY - 40 - surge * 26 + math.cos(waveT1 * 1.1) * 6.0,
      w * 0.86, baseY - 18 - surge * 16 + math.sin(waveT1 * 1.4) * 5.0,
      w + 20, baseY - 26 - surge * 20,
    );
    pathSteamBack.lineTo(w + 20, h + 10);
    pathSteamBack.close();

    final paintSteamBack = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFFF0FAF7).withValues(alpha: 0.40 * alphaMod),
                const Color(0xFFC4DDD6).withValues(alpha: 0.55 * alphaMod),
                const Color(0xFF334640).withValues(alpha: 0.80 * alphaMod),
              ]
            : [
                Colors.white.withValues(alpha: 0.65 * alphaMod),
                const Color(0xFFE2F0EA).withValues(alpha: 0.80 * alphaMod),
                const Color(0xFFB8D9CC).withValues(alpha: 0.90 * alphaMod),
              ],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(Rect.fromLTWH(0, baseY - 70, w, 80))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawPath(pathSteamBack, paintSteamBack);

    // 4. Foreground Rolling Deluge Steam Wave
    final pathSteamFront = Path()
      ..moveTo(-20, h + 10)
      ..lineTo(-20, baseY - 8 - surge * 14);

    final double waveT2 = smokeValue * math.pi * 2.6 + 1.2;
    pathSteamFront.cubicTo(
      w * 0.28, baseY - 22 - surge * 18 + math.sin(waveT2) * 5.0,
      w * 0.48, baseY - 36 - surge * 26 + math.cos(waveT2) * 6.0,
      w * 0.65, baseY - 24 - surge * 20 + math.sin(waveT2 * 1.2) * 5.0,
    );
    pathSteamFront.cubicTo(
      w * 0.82, baseY - 12 - surge * 12 + math.cos(waveT2 * 1.5) * 4.0,
      w * 0.94, baseY - 18 - surge * 14,
      w + 20, baseY - 10 - surge * 10,
    );
    pathSteamFront.lineTo(w + 20, h + 10);
    pathSteamFront.close();

    final Color frontCoreGlow = (isLaunching && blastValue <= 0.35)
        ? const Color(0xFFFFF6D8)
        : Colors.white;

    final paintSteamFront = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                frontCoreGlow.withValues(alpha: 0.70 * alphaMod),
                const Color(0xFFE0F4EE).withValues(alpha: 0.55 * alphaMod),
                const Color(0xFF425A52).withValues(alpha: 0.75 * alphaMod),
              ]
            : [
                frontCoreGlow.withValues(alpha: 0.88 * alphaMod),
                const Color(0xFFE8F6F1).withValues(alpha: 0.85 * alphaMod),
                const Color(0xFFC0DFD3).withValues(alpha: 0.92 * alphaMod),
              ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, baseY - 50, w, 60))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(pathSteamFront, paintSteamFront);

    // 5. Rising Steam Wisps drifting upwards from pad
    const int wispCount = 4;
    for (int i = 0; i < wispCount; i++) {
      final double cycle = (smokeValue * 1.8 + (i / wispCount)) % 1.0;
      final double wx = w * (0.28 + i * 0.14) + math.sin(cycle * math.pi * 2 + i) * 12.0;
      final double wy = baseY - 14.0 - surge * 18.0 - cycle * (32.0 + surge * 20.0);
      final double wRadius = 14.0 + cycle * 18.0 + surge * 8.0;
      final double wOpacity = math.sin(cycle * math.pi) * (isDark ? 0.35 : 0.50) * alphaMod;

      _drawSoftVaporPuff(
        canvas,
        center: Offset(wx, wy),
        radius: wRadius,
        color: isDark ? const Color(0xFFE8F8F2) : Colors.white,
        blurSigma: 14.0,
        opacity: wOpacity,
      );
    }
  }

  void _drawIdleThrusterWisps(Canvas canvas, Size size) {
    if (blastValue > 0.18) return; // Flight contrail takes over after liftoff

    final rocketCenter = RocketUpdateHeader.computeRocketCenter(
      progress: blastValue,
      cardWidth: size.width,
      cardHeight: size.height,
    );
    final nozzle = RocketUpdateHeader.computeNozzlePosition(rocketCenter);
    final double baseY = size.height - 8.0;

    // Thruster vector pointing downwards-left along exhaust axis
    const double flightAngle = -math.pi / 4;
    final double ex = -math.cos(flightAngle);
    final double ey = -math.sin(flightAngle);

    final double power = isDownloading ? (0.35 + downloadProgress * 0.65) : 0.25;
    const int wispCount = 5;

    for (int i = 0; i < wispCount; i++) {
      final double cycle = (smokeValue * (2.2 + power * 1.5) + (i / wispCount)) % 1.0;
      final double distance = 10.0 + cycle * 70.0;
      final double px = nozzle.dx + ex * distance + math.sin(cycle * math.pi * 3 + i) * (2.5 + cycle * 5.0);
      final double py = nozzle.dy + ey * distance;

      if (py >= baseY + 10.0) continue;

      final double radius = 8.0 + cycle * 16.0 + power * 4.0;
      final double opacity = math.sin(cycle * math.pi) * (isDark ? 0.45 : 0.60) * power;

      final Color puffColor = cycle < 0.22
          ? const Color(0xFFFFDFA6)
          : (isDark ? const Color(0xFFEDF8F4) : Colors.white);

      _drawSoftVaporPuff(
        canvas,
        center: Offset(px, py),
        radius: radius,
        color: puffColor,
        blurSigma: 8.0 + cycle * 6.0,
        opacity: opacity,
      );
    }
  }

  void _drawFlightExhaustSmoke(Canvas canvas, Size size) {
    if (blastValue <= 0.18) return; // Plume emerges once liftoff begins

    const int stationCount = 18;
    final List<Offset> centerPoints = [];
    final List<double> stationFracs = [];

    const double flightAngle = -math.pi / 4;
    const double normAngle = flightAngle + math.pi / 2;
    final double nx = math.cos(normAngle);
    final double ny = math.sin(normAngle);
    final double bx = -math.cos(flightAngle);
    final double by = -math.sin(flightAngle);

    // 1. Sample trajectory points backward from current nozzle position
    for (int k = 0; k <= stationCount; k++) {
      final double frac = k / stationCount;
      final double sampleProgress = blastValue - (k * 0.024);
      if (sampleProgress < 0.16) {
        if (centerPoints.isNotEmpty) break;
        continue;
      }

      final ptCenter = RocketUpdateHeader.computeRocketCenter(
        progress: sampleProgress,
        cardWidth: size.width,
        cardHeight: size.height,
      );
      final ptNozzle = RocketUpdateHeader.computeNozzlePosition(ptCenter);
      centerPoints.add(ptNozzle);
      stationFracs.add(frac);
    }

    if (centerPoints.length < 2) return;

    final currentNozzle = centerPoints.first;
    final tailCenter = centerPoints.last;

    // 2. Compute smooth fluid boundary points with harmonic Kelvin-Helmholtz billow waves
    final List<Offset> outerLeft = [];
    final List<Offset> outerRight = [];
    final List<Offset> innerLeft = [];
    final List<Offset> innerRight = [];

    for (int i = 0; i < centerPoints.length; i++) {
      final double frac = stationFracs[i];
      final Offset pt = centerPoints[i];

      // Smooth expansion: starts tight at nozzle, expands volumetrically downstream
      final double outerWidth = 7.0 + math.pow(frac, 0.65) * 38.0;
      final double innerWidth = 4.5 + math.pow(frac, 0.65) * 26.0;

      // Harmonic fluid shear turbulence
      final double waveL = math.sin(frac * 8.5 - smokeValue * (math.pi * 4.5)) * (2.0 + frac * 4.5)
          + math.cos(frac * 15.0 - smokeValue * (math.pi * 3)) * (1.2 + frac * 2.0);
      final double waveR = math.cos(frac * 8.0 - smokeValue * (math.pi * 4.5) + 1.2) * (2.0 + frac * 4.5)
          + math.sin(frac * 14.0 - smokeValue * (math.pi * 3)) * (1.2 + frac * 2.0);

      outerLeft.add(Offset(
        pt.dx + nx * (outerWidth + waveL),
        pt.dy + ny * (outerWidth + waveL),
      ));
      outerRight.add(Offset(
        pt.dx - nx * (outerWidth + waveR),
        pt.dy - ny * (outerWidth + waveR),
      ));

      innerLeft.add(Offset(
        pt.dx + nx * (innerWidth + waveL * 0.7),
        pt.dy + ny * (innerWidth + waveL * 0.7),
      ));
      innerRight.add(Offset(
        pt.dx - nx * (innerWidth + waveR * 0.7),
        pt.dy - ny * (innerWidth + waveR * 0.7),
      ));
    }

    // Helper to build a continuous curved polygon from left and right point lists
    Path buildContrailPath(List<Offset> leftPts, List<Offset> rightPts) {
      final path = Path()..moveTo(leftPts.first.dx, leftPts.first.dy);
      for (int i = 1; i < leftPts.length; i++) {
        final mid = Offset(
          (leftPts[i - 1].dx + leftPts[i].dx) * 0.5,
          (leftPts[i - 1].dy + leftPts[i].dy) * 0.5,
        );
        path.quadraticBezierTo(leftPts[i - 1].dx, leftPts[i - 1].dy, mid.dx, mid.dy);
      }
      path.lineTo(leftPts.last.dx, leftPts.last.dy);

      // Rounded tail end
      final tailEnd = Offset(
        tailCenter.dx + bx * 18.0,
        tailCenter.dy + by * 18.0,
      );
      path.quadraticBezierTo(tailEnd.dx, tailEnd.dy, rightPts.last.dx, rightPts.last.dy);

      for (int i = rightPts.length - 1; i > 0; i--) {
        final mid = Offset(
          (rightPts[i - 1].dx + rightPts[i].dx) * 0.5,
          (rightPts[i - 1].dy + rightPts[i].dy) * 0.5,
        );
        path.quadraticBezierTo(rightPts[i].dx, rightPts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(rightPts.first.dx, rightPts.first.dy);
      path.close();
      return path;
    }

    // 3. PASS 1: Outer Atmospheric Vapor Haze (Heavy Gaussian Blur)
    // Produces the soft, misty, ethereal atmospheric boundary of real rocket plumes
    final outerPath = buildContrailPath(outerLeft, outerRight);
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(
          (currentNozzle.dx / size.width) * 2 - 1,
          (currentNozzle.dy / size.height) * 2 - 1,
        ),
        end: Alignment(
          (tailCenter.dx / size.width) * 2 - 1,
          (tailCenter.dy / size.height) * 2 - 1,
        ),
        colors: isDark
            ? [
                const Color(0xFFFFB347).withValues(alpha: 0.70),
                const Color(0xFFE8F6F1).withValues(alpha: 0.45),
                const Color(0xFF90B0A6).withValues(alpha: 0.30),
                const Color(0xFF334640).withValues(alpha: 0.15),
                Colors.transparent,
              ]
            : [
                const Color(0xFFFFB347).withValues(alpha: 0.75),
                Colors.white.withValues(alpha: 0.55),
                const Color(0xFFD4EAE2).withValues(alpha: 0.40),
                const Color(0xFFA8D0C0).withValues(alpha: 0.18),
                Colors.transparent,
              ],
        stops: const [0.0, 0.18, 0.50, 0.82, 1.0],
      ).createShader(Rect.fromPoints(currentNozzle, tailCenter))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawPath(outerPath, outerPaint);

    // 4. PASS 2: Dense Volumetric Cloud Body (The Main Billowing Plume)
    // A continuous, dense fluid steam core with soft Gaussian diffusion
    final innerPath = buildContrailPath(innerLeft, innerRight);
    final innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(
          (currentNozzle.dx / size.width) * 2 - 1,
          (currentNozzle.dy / size.height) * 2 - 1,
        ),
        end: Alignment(
          (tailCenter.dx / size.width) * 2 - 1,
          (tailCenter.dy / size.height) * 2 - 1,
        ),
        colors: isDark
            ? [
                const Color(0xFFFFF7DB).withValues(alpha: 0.95), // Blinding white-gold at nozzle
                const Color(0xFFFFFFFF).withValues(alpha: 0.85), // Pure milky steam
                const Color(0xFFE2EFEA).withValues(alpha: 0.70), // Dense cloud volume
                const Color(0xFF4A625A).withValues(alpha: 0.40), // Soft atmospheric ash shadow
                Colors.transparent,
              ]
            : [
                const Color(0xFFFFF7DB).withValues(alpha: 0.95),
                Colors.white.withValues(alpha: 0.90),
                const Color(0xFFF2FAF6).withValues(alpha: 0.78),
                const Color(0xFFBFDEC2).withValues(alpha: 0.45),
                Colors.transparent,
              ],
        stops: const [0.0, 0.15, 0.45, 0.78, 1.0],
      ).createShader(Rect.fromPoints(currentNozzle, tailCenter))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(innerPath, innerPaint);

    // 5. PASS 3: Rolling Asymmetric Cloud Billow Knots
    // Soft, Gaussian-diffused cloud puffs positioned along the plume to create puffy cumulus mounds
    for (int i = 1; i < centerPoints.length; i += 2) {
      final double frac = stationFracs[i];
      final Offset pt = centerPoints[i];
      final double r = 12.0 + math.pow(frac, 0.65) * 24.0;
      final double op = (1.0 - math.pow(frac, 1.3) * 0.85).clamp(0.0, 0.80);

      // Alternating lateral offset for natural fluid billows
      final double side = (i % 4 == 1) ? 1.0 : -1.0;
      final double latOffset = (3.0 + frac * 12.0) * side;
      final Offset billowCenter = Offset(
        pt.dx + nx * latOffset,
        pt.dy + ny * latOffset,
      );

      final Color billowColor = frac < 0.20
          ? const Color(0xFFFFF3D0)
          : (isDark ? const Color(0xFFF4FAF7) : Colors.white);

      _drawSoftVaporPuff(
        canvas,
        center: billowCenter,
        radius: r,
        color: billowColor,
        blurSigma: 10.0 + frac * 4.0,
        opacity: op,
      );
    }

    // 6. PASS 4: Supersonic Incandescent Jet Core & Mach Shock Diamonds
    // High-pressure needle core right at the engine nozzle
    final int jetLength = (centerPoints.length * 0.35).round().clamp(2, centerPoints.length);
    final jetPath = Path()..moveTo(currentNozzle.dx + nx * 4.0, currentNozzle.dy + ny * 4.0);
    for (int i = 1; i < jetLength; i++) {
      final double frac = i / jetLength;
      final double wCore = 4.0 + frac * 8.0;
      final pt = centerPoints[i];
      jetPath.lineTo(pt.dx + nx * wCore, pt.dy + ny * wCore);
    }
    for (int i = jetLength - 1; i >= 0; i--) {
      final double frac = i / jetLength;
      final double wCore = 4.0 + frac * 8.0;
      final pt = centerPoints[i];
      jetPath.lineTo(pt.dx - nx * wCore, pt.dy - ny * wCore);
    }
    jetPath.close();

    final jetPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(
          (currentNozzle.dx / size.width) * 2 - 1,
          (currentNozzle.dy / size.height) * 2 - 1,
        ),
        end: Alignment(
          (centerPoints[jetLength - 1].dx / size.width) * 2 - 1,
          (centerPoints[jetLength - 1].dy / size.height) * 2 - 1,
        ),
        colors: [
          Colors.white.withValues(alpha: 0.95),
          const Color(0xFFFFE082).withValues(alpha: 0.85),
          const Color(0xFFFF9500).withValues(alpha: 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.30, 0.75, 1.0],
      ).createShader(Rect.fromPoints(currentNozzle, centerPoints[jetLength - 1]))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawPath(jetPath, jetPaint);

    // Supersonic Mach Shock Diamonds
    final diamondPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    for (final frac in [0.08, 0.18, 0.30]) {
      final int idx = (frac * (centerPoints.length - 1)).round();
      if (idx >= centerPoints.length) continue;
      final pt = centerPoints[idx];
      const double dSize = 3.5;
      final diamond = Path()
        ..moveTo(pt.dx + bx * dSize * 1.5, pt.dy + by * dSize * 1.5)
        ..lineTo(pt.dx + nx * dSize, pt.dy + ny * dSize)
        ..lineTo(pt.dx - bx * dSize * 1.5, pt.dy - by * dSize * 1.5)
        ..lineTo(pt.dx - nx * dSize, pt.dy - ny * dSize)
        ..close();
      canvas.drawPath(diamond, diamondPaint);
    }

    // 7. PASS 5: Delicate Slipstream Vapor Wisps
    const int wispCount = 4;
    for (int w = 0; w < wispCount; w++) {
      final double wFrac = (w + 0.5) / wispCount;
      final int idx = (wFrac * (centerPoints.length - 1)).round();
      if (idx >= centerPoints.length) continue;
      final pt = centerPoints[idx];
      final double side = (w % 2 == 0) ? 1.0 : -1.0;
      final double curlDist = (18.0 + wFrac * 22.0) * side;
      final double curlPhase = smokeValue * math.pi * 3.5 + w * 1.7;
      final Offset wispPos = Offset(
        pt.dx + nx * (curlDist + math.sin(curlPhase) * 5.0),
        pt.dy + ny * (curlDist + math.cos(curlPhase) * 5.0),
      );

      final double wispRadius = 8.0 + wFrac * 10.0;
      final double wispOpacity = (0.45 * (1.0 - wFrac)).clamp(0.08, 0.45);

      _drawSoftVaporPuff(
        canvas,
        center: wispPos,
        radius: wispRadius,
        color: isDark ? const Color(0xFFE8F8F2) : Colors.white,
        blurSigma: 10.0,
        opacity: wispOpacity,
      );
    }
  }

  void _drawRocket(Canvas canvas, Size size) {
    canvas.save();

    const double baseFlightAngle = -math.pi / 4;

    // Use unified coordinate calculator to guarantee 100% synchronization with particle system
    final rocketCenter = RocketUpdateHeader.computeRocketCenter(
      progress: blastValue,
      cardWidth: size.width,
      cardHeight: size.height,
    );
    double posX = rocketCenter.dx;
    double posY = rocketCenter.dy;

    if (blastValue <= 0.001) {
      final double hoverOffset = (hoverValue - 0.5) * 8.0;
      posX += hoverOffset * 0.5;
      posY += hoverOffset;
    }

    canvas.translate(posX, posY);
    canvas.rotate(baseFlightAngle + math.pi / 2);

    if (blastValue > 0.18) {
      final double tFlight = ((blastValue - 0.18) / 0.82).clamp(0.0, 1.0);
      final double scale = 1.0 - tFlight * 0.25;
      canvas.scale(scale, scale);
    }

    // A. Draw Thruster Flame (glued to nozzle, pointing strictly backward)
    _drawThrusterFlame(canvas);

    // B. Draw Left Fin
    final leftFinPath = Path()
      ..moveTo(-16, 28)
      ..lineTo(-36, 44)
      ..quadraticBezierTo(-34, 54, -20, 52)
      ..lineTo(-12, 42)
      ..close();
    final finPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFDF73),
          Color(0xFFDAA464),
          Color(0xFF8A6327),
        ],
      ).createShader(const Rect.fromLTWH(-36, 28, 26, 26));
    canvas.drawPath(leftFinPath, finPaint);

    // C. Draw Right Fin
    final rightFinPath = Path()
      ..moveTo(16, 28)
      ..lineTo(36, 44)
      ..quadraticBezierTo(34, 54, 20, 52)
      ..lineTo(12, 42)
      ..close();
    canvas.drawPath(rightFinPath, finPaint);

    // D. Rocket Fuselage
    final fuselagePath = Path()
      ..moveTo(0, -56)
      ..cubicTo(26, -30, 24, 20, 16, 40)
      ..lineTo(-16, 40)
      ..cubicTo(-24, 20, -26, -30, 0, -56)
      ..close();

    final fuselagePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF095A45),
          Color(0xFF13A383),
          Color(0xFF22C59E),
          Color(0xFF074837),
        ],
        stops: [0.0, 0.45, 0.70, 1.0],
      ).createShader(const Rect.fromLTWH(-24, -56, 48, 96));
    canvas.drawPath(fuselagePath, fuselagePaint);

    final highlightPath = Path()
      ..moveTo(-4, -48)
      ..quadraticBezierTo(8, -15, 6, 32)
      ..lineTo(2, 32)
      ..quadraticBezierTo(4, -15, -6, -48)
      ..close();
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawPath(highlightPath, highlightPaint);

    // E. Nose Cone
    final nosePath = Path()
      ..moveTo(0, -56)
      ..cubicTo(12, -44, 15, -34, 16, -26)
      ..lineTo(-16, -26)
      ..cubicTo(-15, -34, -12, -44, 0, -56)
      ..close();
    final nosePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFDF73),
          Color(0xFFDAA464),
          Color(0xFF96682A),
        ],
      ).createShader(const Rect.fromLTWH(-16, -56, 32, 30));
    canvas.drawPath(nosePath, nosePaint);

    // F. Central Dorsal Fin
    final centerFinPath = Path()
      ..moveTo(0, -12)
      ..lineTo(3.5, 38)
      ..lineTo(-3.5, 38)
      ..close();
    final centerFinPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFFDF73),
          Color(0xFFDAA464),
        ],
      ).createShader(const Rect.fromLTWH(-3.5, -12, 7, 50));
    canvas.drawPath(centerFinPath, centerFinPaint);

    // G. Circular Porthole Window
    const double portholeY = 2.0;
    const double portholeRadius = 12.0;

    final rimPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFDF73),
          Color(0xFFDAA464),
          Color(0xFF7A5420),
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, portholeY), radius: portholeRadius));
    canvas.drawCircle(const Offset(0, portholeY), portholeRadius, rimPaint);

    final glassPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.35),
        colors: [
          Color(0xFF13A383),
          Color(0xFF04281E),
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, portholeY), radius: portholeRadius - 2.8));
    canvas.drawCircle(const Offset(0, portholeY), portholeRadius - 2.8, glassPaint);

    final glarePath = Path()
      ..addArc(Rect.fromCircle(center: const Offset(0, portholeY), radius: portholeRadius - 4.5), -1.8, 1.6);
    final glarePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    canvas.drawPath(glarePath, glarePaint);

    // H. Exhaust Nozzle
    final nozzlePath = Path()
      ..moveTo(-11, 40)
      ..lineTo(-14, 48)
      ..lineTo(14, 48)
      ..lineTo(11, 40)
      ..close();
    final nozzlePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFDAA464),
          Color(0xFF7A5420),
          Color(0xFFDAA464),
        ],
      ).createShader(const Rect.fromLTWH(-14, 40, 28, 8));
    canvas.drawPath(nozzlePath, nozzlePaint);

    canvas.restore();
  }

  void _drawThrusterFlame(Canvas canvas) {
    final bool isLaunching = blastValue > 0.0;
    final double flicker1 = math.sin(hoverValue * math.pi * 14);
    final double flicker2 = math.cos(hoverValue * math.pi * 11);
    final double flicker3 = math.sin(hoverValue * math.pi * 18 + 0.8);

    final double flameLength;
    final double flameWidth;

    if (isLaunching) {
      if (blastValue <= 0.18) {
        // Phase 1: Pad Ignition (sleek rev-up, tightly contained)
        final double igniteFactor = (blastValue / 0.18);
        flameLength = 22.0 + igniteFactor * 12.0 + flicker1 * 2.5;
        flameWidth = 9.5 + igniteFactor * 1.5 + flicker2 * 0.8;
      } else {
        // Phase 2: Supersonic liftoff (sleek high-velocity needle jet, strictly ~45% rocket length)
        final double tFlight = ((blastValue - 0.18) / 0.82).clamp(0.0, 1.0);
        flameLength = 36.0 + tFlight * 10.0 + flicker1 * 2.5;
        flameWidth = 11.0 + flicker2 * 1.0;
      }
    } else if (isDownloading) {
      // Thrusters powering up in proportion to download progress
      final double power = downloadProgress.clamp(0.0, 1.0);
      flameLength = 16.0 + power * 12.0 + flicker1 * 2.0;
      flameWidth = 8.5 + power * 2.0 + flicker2 * 0.8;
    } else {
      // Idle gentle hover thrust
      flameLength = 14.0 + flicker1 * 2.0;
      flameWidth = 8.0 + flicker2 * 0.8;
    }

    // Layer 0: Subtle, focused nozzle throat heat glow
    final double glowRadius = (flameLength * 0.45).clamp(10.0, 22.0);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF9500).withValues(alpha: isLaunching ? 0.28 : (isDownloading ? 0.18 : 0.10)),
          const Color(0xFFFF3B30).withValues(alpha: isLaunching ? 0.12 : (isDownloading ? 0.08 : 0.03)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(0, 48 + flameLength * 0.35), radius: glowRadius));
    canvas.drawCircle(Offset(0, 48 + flameLength * 0.35), glowRadius, glowPaint);

    // Layer 1: Main Aerodynamic Supersonic Exhaust Plume (seated cleanly inside nozzle)
    final mainPath = Path()
      ..moveTo(-flameWidth, 48)
      ..quadraticBezierTo(
        -flameWidth * 0.85 + flicker2 * 1.5,
        48 + flameLength * 0.45,
        -flameWidth * 0.35 + flicker3 * 1.5,
        48 + flameLength * 0.80,
      )
      ..lineTo(flicker1 * 1.5, 48 + flameLength)
      ..quadraticBezierTo(
        flameWidth * 0.35 - flicker3 * 1.5,
        48 + flameLength * 0.80,
        flameWidth * 0.85 - flicker2 * 1.5,
        48 + flameLength * 0.45,
      )
      ..lineTo(flameWidth, 48)
      ..close();

    final mainPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFDF73), // Brilliant gold at nozzle
          Color(0xFFFF9500), // Rich amber
          Color(0xFFFF3B30), // Blazing red-orange
          Colors.transparent,
        ],
        stops: [0.0, 0.30, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(-flameWidth, 48, flameWidth * 2, flameLength));
    canvas.drawPath(mainPath, mainPaint);

    // Layer 2: Mid-layer Golden Core
    final double coreWidth = flameWidth * 0.58;
    final double coreLength = flameLength * 0.65;
    final corePath = Path()
      ..moveTo(-coreWidth, 48)
      ..quadraticBezierTo(-coreWidth * 0.7 + flicker1 * 1.0, 48 + coreLength * 0.5, 0, 48 + coreLength)
      ..quadraticBezierTo(coreWidth * 0.7 - flicker2 * 1.0, 48 + coreLength * 0.5, coreWidth, 48)
      ..close();

    final corePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFBE8), // Bright white-gold
          Color(0xFFFFDF73), // Gold
          Color(0xFFFF9500), // Amber
          Colors.transparent,
        ],
        stops: [0.0, 0.30, 0.70, 1.0],
      ).createShader(Rect.fromLTWH(-coreWidth, 48, coreWidth * 2, coreLength));
    canvas.drawPath(corePath, corePaint);

    // Layer 3: Supersonic Mach Shock Diamonds
    if (isLaunching || isDownloading) {
      final diamondPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0xFFFFDF73),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(-5, 48, 10, flameLength));

      final int diamondCount = isLaunching ? 2 : 1;
      for (int i = 1; i <= diamondCount; i++) {
        final double dY = 48 + flameLength * (i * 0.28);
        const double dSize = 3.2;
        final diamond = Path()
          ..moveTo(0, dY - dSize)
          ..lineTo(dSize * 0.7, dY)
          ..lineTo(0, dY + dSize)
          ..lineTo(-dSize * 0.7, dY)
          ..close();
        canvas.drawPath(diamond, diamondPaint);
      }
    }

    // Layer 4: Incandescent White-Hot Plasma Needle
    final double lanceWidth = flameWidth * 0.25;
    final double lanceLength = flameLength * 0.38;
    final lancePath = Path()
      ..moveTo(-lanceWidth, 48)
      ..quadraticBezierTo(-lanceWidth * 0.4, 48 + lanceLength * 0.5, 0, 48 + lanceLength)
      ..quadraticBezierTo(lanceWidth * 0.4, 48 + lanceLength * 0.5, lanceWidth, 48)
      ..close();

    final lancePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white,
          Color(0xFFFFDF73),
          Colors.transparent,
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(-lanceWidth, 48, lanceWidth * 2, lanceLength));
    canvas.drawPath(lancePath, lancePaint);

    // Layer 5: Nozzle Ring Energy Highlight
    final rimHaloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFDF73).withValues(alpha: 0.90),
          const Color(0xFF13A383).withValues(alpha: 0.50),
          Colors.transparent,
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(const Rect.fromLTWH(-12, 44, 24, 8));
    canvas.drawOval(const Rect.fromLTWH(-12, 45, 24, 5), rimHaloPaint);
  }

  @override
  bool shouldRepaint(covariant _RocketSpacePainter oldDelegate) => true;
}
