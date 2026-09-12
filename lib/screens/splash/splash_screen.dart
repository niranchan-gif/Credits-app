import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/notification_service.dart';
import '../../services/auto_backup_manager.dart';
import '../../services/google_drive_service.dart';
import '../app_lock_wrapper.dart';
import '../auth/sign_in_screen.dart';
import '../main_navigation_screen.dart';
import '../../services/update_service.dart';
import '../force_update_screen.dart';
import '../../utils/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  bool _backendInitialized = false;
  bool _animationMinimumReached = false;
  bool _navigated = false;
  bool _isSignedIn = false;
  UpdateCheckResult? _updateResult;

  // Background color matching the unified brand palette
  final Color _bgColor = AppColors.brandBackground;

  late AnimationController _animController;
  late Animation<double> _dropAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _spinAnim;
  late Animation<double> _textFadeAnim;
  late Animation<double> _textScaleAnim;
  late Animation<double> _letterSpacingAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // Coin Toss: Up then Down
    _dropAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -200).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -200, end: 0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65)),
    );

    // Fake depth by scaling up as it tosses
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 60,
      ),
    ]).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65)),
    );

    // 9 * pi = 4.5 spins.
    _spinAnim = Tween<double>(begin: 0, end: 9 * math.pi).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65, curve: Curves.easeInOutCubic)),
    );

    _textFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeIn)),
    );

    _textScaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeOutBack)),
    );

    _letterSpacingAnim = Tween<double>(begin: 20.0, end: 6.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeOutCubic)),
    );

    _animController.forward();

    // Start background services asynchronously without blocking the animation ticker
    _initBackendConcurrently();

    // Minimum animation duration ensures smooth cinematic completion
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        _animationMinimumReached = true;
        _checkAndNavigate();
      }
    });

    // Safety fallback timeout
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && !_navigated) {
        _checkAndNavigate(force: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache the app icon image texture so the 3D flip has 0ms GPU rasterization delay
    precacheImage(const AssetImage('assets/icon/app_icon.png'), context);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initBackendConcurrently() async {
    final startTime = DateTime.now();
    debugPrint('SplashScreen: Concurrently initializing backend services...');

    try {
      final driveFuture = GoogleDriveService().isConnected().catchError((_) => false);
      final updateFuture = UpdateService().checkForUpdates().then<UpdateCheckResult?>((res) => res).catchError((e) {
        debugPrint('Update check error: $e');
        return null;
      });
      final notifFuture = NotificationService().init().catchError((_) {});

      _isSignedIn = await driveFuture;
      _updateResult = await updateFuture;
      await notifFuture;

      try {
        AutoBackupManager().start();
      } catch (_) {}
    } catch (e) {
      debugPrint('SplashScreen backend init error: $e');
    }

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('SplashScreen: Backend services initialized in $elapsed ms.');

    if (mounted) {
      _backendInitialized = true;
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate({bool force = false}) {
    if ((force || (_animationMinimumReached && _backendInitialized)) && !_navigated) {
      _navigated = true;
      Widget nextScreen;
      Widget appScreen = _isSignedIn
          ? const AppLockWrapper(child: MainNavigationScreen())
          : const SignInScreen();

      if (_updateResult != null &&
          (_updateResult!.status == UpdateStatus.mandatoryUpdate || _updateResult!.status == UpdateStatus.optionalUpdate) &&
          _updateResult!.updateInfo != null) {
        nextScreen = ForceUpdateScreen(
          updateInfo: _updateResult!.updateInfo!,
          currentBuild: _updateResult!.currentBuild,
          nextScreen: appScreen,
        );
      } else {
        nextScreen = appScreen;
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          opaque: false, // Prevents Flutter from blacking/whiting out the splash screen during transition
          pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: fadeAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 1000), // Slower cinematic transition
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // 1. Static Premium Top Light Flare & Tech Grid (Painted ONCE & cached on GPU)
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StaticBackdropPainter(),
              ),
            ),
          ),

          // 2. Animated Elements driven by _animController
          AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              final angle = _spinAnim.value;

              return Stack(
                children: [
                  // Lightweight Floating Bokeh Particles
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _BokehParticlesPainter(_animController.value),
                      ),
                    ),
                  ),

                  // Premium Bargraph Shadow anchored to the absolute bottom (4 bars)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: RepaintBoundary(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildShadowBar(
                            height: 100 * _getBarProgress(0, _animController.value),
                            opacity: _getBarProgress(0, _animController.value),
                          ),
                          const SizedBox(width: 25),
                          _buildShadowBar(
                            height: 160 * _getBarProgress(1, _animController.value),
                            opacity: _getBarProgress(1, _animController.value),
                          ),
                          const SizedBox(width: 25),
                          _buildShadowBar(
                            height: 240 * _getBarProgress(2, _animController.value),
                            opacity: _getBarProgress(2, _animController.value),
                          ),
                          const SizedBox(width: 25),
                          _buildShadowBar(
                            height: 320 * _getBarProgress(3, _animController.value),
                            opacity: _getBarProgress(3, _animController.value),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Main Content: 3D Flipping Coin & Brand Typography
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Emerald Ambient Aura
                            FadeTransition(
                              opacity: _textFadeAnim,
                              child: Container(
                                width: 250,
                                height: 250,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0x5913A383),
                                      Color(0x0013A383),
                                    ],
                                    stops: [0.0, 1.0],
                                  ),
                                ),
                              ),
                            ),

                            Transform.translate(
                              offset: Offset(0, _dropAnim.value),
                              child: Transform.scale(
                                scale: _scaleAnim.value,
                                child: _buildCoin(angle),
                              ),
                            ),
                          ],
                        ),

                        // Title and Subtitle with Smooth Reveal
                        Transform.translate(
                          offset: const Offset(0, -40),
                          child: Transform.scale(
                            scale: _textScaleAnim.value,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Credits',
                                  style: GoogleFonts.leagueSpartan(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.95 * _textFadeAnim.value),
                                    letterSpacing: _letterSpacingAnim.value * 0.5,
                                    shadows: [
                                      Shadow(
                                        color: const Color(0xFF13A383).withValues(alpha: 0.5 * _textFadeAnim.value),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '',
                                  style: GoogleFonts.manrope(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFDAA464).withValues(alpha: 0.85 * _textFadeAnim.value),
                                    letterSpacing: 3.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  double _getBarProgress(int index, double progress) {
    const double duration = 0.30;
    final double start = index * (0.65 / 3.0);
    final double end = start + duration;

    if (progress <= start) return 0.0;
    if (progress >= end) return 1.0;

    final double t = (progress - start) / (end - start);
    return Curves.easeOutBack.transform(t);
  }

  Widget _buildShadowBar({required double height, required double opacity}) {
    final double safeOpacity = opacity.clamp(0.0, 1.0);

    return Container(
      width: 60,
      height: height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF063628).withValues(alpha: safeOpacity),
            const Color(0xFF021711).withValues(alpha: 0.2 * safeOpacity),
          ],
        ),
      ),
    );
  }

  Widget _buildCoin(double angle) {
    final isFront = math.cos(angle) > 0;

    return RepaintBoundary(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002) // Sleek 3D perspective
          ..rotateY(angle),
        child: isFront
            ? _buildRupeeSide(angle)
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: _buildLogoSide(angle),
              ),
      ),
    );
  }

  Widget _buildGlassyFace({required Widget child, required double angle}) {
    const double coinSize = 160.0;
    final double sweep = math.sin(angle * 1.5);

    return Container(
      width: coinSize,
      height: coinSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFDF73),
            Color(0xFF8A6327),
            Color(0xFFFFDF73),
            Color(0xFF8A6327),
            Color(0xFFFFDF73),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xBB13A383),
                Color(0x77096853),
                Color(0x44042B22),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              child,

              // Glassy top highlight arc
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: coinSize * 0.45,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(coinSize / 2)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.6),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // Specular shine sweep
              ClipOval(
                child: Transform.translate(
                  offset: Offset(sweep * coinSize * 1.5, 0),
                  child: Container(
                    width: coinSize * 1.5,
                    height: coinSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 0.5),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRupeeSide(double angle) {
    return _buildGlassyFace(
      angle: angle,
      child: const Text(
        '₹',
        style: TextStyle(
          fontSize: 90,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildLogoSide(double angle) {
    return _buildGlassyFace(
      angle: angle,
      child: ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          fit: BoxFit.cover,
          width: 120,
          height: 120,
          cacheWidth: 240,
          cacheHeight: 240,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// Static backdrop (spotlight flare & tech grid). Painted once and cached as a GPU layer.
class _StaticBackdropPainter extends CustomPainter {
  const _StaticBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Top Ambient Spotlight Flare
    final topLightPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -1.0),
        radius: 1.5,
        colors: [
          Color(0x3F13A383),
          Color(0x19096853),
          Color(0x00021711),
        ],
        stops: [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), topLightPaint);

    // 2. Premium Tech Grid
    final gridPaint = Paint()
      ..color = const Color(0x1413A383)
      ..strokeWidth = 1.0;

    const double spacing = 35.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Particle metadata for lightweight bokeh computation
class _ParticleInfo {
  final double normX;
  final double normY;
  final double speed;
  final double radius;
  final Color color;

  const _ParticleInfo({
    required this.normX,
    required this.normY,
    required this.speed,
    required this.radius,
    required this.color,
  });
}

/// Highly optimized organic particle bokeh that paints with zero per-frame shader allocations
class _BokehParticlesPainter extends CustomPainter {
  final double progress;

  _BokehParticlesPainter(this.progress);

  static const List<_ParticleInfo> _particles = [
    _ParticleInfo(normX: 0.15, normY: 0.20, speed: 1.1, radius: 14.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.85, normY: 0.15, speed: 0.8, radius: 22.0, color: Color(0xFFFFDF73)),
    _ParticleInfo(normX: 0.30, normY: 0.45, speed: 1.3, radius: 12.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.70, normY: 0.60, speed: 0.9, radius: 24.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.10, normY: 0.75, speed: 1.2, radius: 18.0, color: Color(0xFFFFDF73)),
    _ParticleInfo(normX: 0.50, normY: 0.10, speed: 1.0, radius: 16.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.90, normY: 0.80, speed: 0.7, radius: 20.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.25, normY: 0.90, speed: 1.4, radius: 13.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.60, normY: 0.35, speed: 1.0, radius: 22.0, color: Color(0xFFFFDF73)),
    _ParticleInfo(normX: 0.40, normY: 0.70, speed: 0.85, radius: 15.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.80, normY: 0.40, speed: 1.15, radius: 19.0, color: Color(0xFF13A383)),
    _ParticleInfo(normX: 0.05, normY: 0.40, speed: 0.95, radius: 17.0, color: Color(0xFF13A383)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      final double startX = p.normX * size.width;
      final double startY = p.normY * size.height;

      double driftY = startY - (progress * 40 * p.speed);
      if (driftY < -50) driftY += size.height + 100;

      final double driftX = startX + math.sin(progress * math.pi * 2 + i) * 25;
      final double twinkle = (0.5 + 0.5 * math.sin(progress * math.pi * 4 + i)).clamp(0.0, 1.0);

      // Draw soft bokeh using 2 fast concentric circles without shader creation overhead
      final outerPaint = Paint()
        ..color = p.color.withValues(alpha: 0.06 * twinkle)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(driftX, driftY), p.radius, outerPaint);

      final innerPaint = Paint()
        ..color = p.color.withValues(alpha: 0.14 * twinkle)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(driftX, driftY), p.radius * 0.5, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BokehParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
