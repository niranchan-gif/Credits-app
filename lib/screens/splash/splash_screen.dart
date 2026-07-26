import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../database/db_helper.dart';
import '../../services/notification_service.dart';
import '../../services/auto_backup_manager.dart';
import '../../providers/theme_provider.dart';
import '../../utils/app_colors.dart';
import '../../providers/loan_provider.dart';
import '../app_lock_wrapper.dart';
import '../main_navigation_screen.dart';
import 'coin_widget.dart';
import 'audio_manager.dart';

class PremiumBackgroundElements extends StatelessWidget {
  final Animation<double> animation;
  final bool isDark;

  const PremiumBackgroundElements({super.key, required this.animation, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Stack(
          children: [
            // Elegant dotted grid background
            CustomPaint(
              size: Size.infinite,
              painter: _GridPainter(
                baseColor: (isDark ? Colors.white : Colors.black),
                progress: animation.value,
              ),
            ),
            // Subtle ambient golden dust particles
            ...List.generate(15, (index) {
              final random = math.Random(index * 42);
              final startX = random.nextDouble() * MediaQuery.of(context).size.width;
              final startY = MediaQuery.of(context).size.height + (random.nextDouble() * 200);
              final speed = 20 + random.nextDouble() * 40; // Very slow drift
              final size = 1.5 + random.nextDouble() * 3.0; // Tiny premium dots
              
              final currentY = startY - (animation.value * speed);
              final opacity = (0.5 - (animation.value * 0.4)).clamp(0.0, 1.0); 
              
              return Positioned(
                left: startX,
                top: currentY,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.8),
                          blurRadius: size * 2,
                          spreadRadius: size * 0.5,
                        )
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color baseColor;
  final double progress;

  _GridPainter({required this.baseColor, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const double spacing = 32.0;
    
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        // Radial fade out from center
        final dx = x - size.width / 2;
        final dy = y - size.height / 2;
        final dist = math.sqrt(dx * dx + dy * dy);
        final maxDist = size.width / 1.1;
        
        double alpha = (1.0 - dist / maxDist).clamp(0.0, 1.0);
        // Base opacity is 15%, fades out as animation progresses
        alpha = alpha * 0.15 * (1.0 - progress * 0.8);
        
        if (alpha > 0) {
          paint.color = baseColor.withValues(alpha: alpha);
          canvas.drawCircle(Offset(x, y), 1.2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.progress != progress;
}

/// Premium Luxury Launch Screen for Credits app.
/// Simultaneously initializes backend services without blocking the UI 60 FPS animation.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  // Animation Tweens
  late Animation<double> _bgOpacity;
  late Animation<double> _coinOpacity;
  late Animation<double> _coinScale;
  late Animation<double> _coinTranslateY;
  late Animation<double> _coinRotation;
  late Animation<double> _shadowOpacity;
  late Animation<double> _shadowScale;
  late Animation<double> _glowOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _textTranslateY;
  late Animation<double> _masterFadeOut;

  bool _backendInitialized = false;
  bool _animationMinimumReached = false;
  bool _navigated = false;

  // Sound triggers state tracking
  bool _whooshPlayed = false;
  int _spinChimesPlayed = 0;
  bool _revealChimePlayed = false;

  @override
  void initState() {
    super.initState();
    AudioManager().init();

    // Total animation timeline: 2.4 seconds (2400 ms) to guarantee app opens in under 3 seconds
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _setupAnimations();
    _setupAudioTriggers();

    // Start UI Animation immediately
    _controller.forward().then((_) {
      if (mounted) {
        _animationMinimumReached = true;
        _checkAndNavigate(force: true);
      }
    });

    // Ensure we ALWAYS transition to home screen within 2.5 seconds maximum
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && !_navigated) {
        _checkAndNavigate(force: true);
      }
    });

    // Simultaneously initialize backend services
    _initBackendConcurrently();
  }

  void _setupAnimations() {
    // 0.0s: Background & Coin start immediately visible at 100% for zero-flicker OS transition
    _bgOpacity = ConstantTween<double>(1.0).animate(_controller);
    _coinOpacity = ConstantTween<double>(1.0).animate(_controller);
    _coinScale = ConstantTween<double>(1.0).animate(_controller);

    // 0.0s - 0.2s (0.000 -> 0.083): Coin lifts upward ~12px
    _coinTranslateY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 8.3,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(-12.0), weight: 79.2),
      TweenSequenceItem(
        tween: Tween<double>(begin: -12.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12.5,
      ),
    ]).animate(_controller);

    // Soft Shadow underneath coin
    _shadowOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.45), weight: 87.5),
      TweenSequenceItem(tween: Tween<double>(begin: 0.45, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 12.5),
    ]).animate(_controller);

    _shadowScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.85).chain(CurveTween(curve: Curves.easeInOut)), weight: 8.3),
      TweenSequenceItem(tween: ConstantTween<double>(0.85), weight: 79.2),
      TweenSequenceItem(tween: Tween<double>(begin: 0.85, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 12.5),
    ]).animate(_controller);

    // 0.2s - 1.8s (0.083 -> 0.750): Natural acceleration & deceleration spin around Y-axis (2.5 turns = 5 * PI)
    _coinRotation = Tween<double>(begin: 0.0, end: 5 * math.pi).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.083, 0.750, curve: Curves.easeInOutCubic),
      ),
    );

    // 1.8s - 2.1s (0.750 -> 0.875): Small elegant glow behind logo when coin stops
    _glowOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 75.0),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.35).chain(CurveTween(curve: Curves.easeOut)), weight: 12.5),
      TweenSequenceItem(tween: Tween<double>(begin: 0.35, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 12.5),
    ]).animate(_controller);

    // 1.8s - 2.4s (0.750 -> 1.000): Typography text fades in and smoothly transitions
    _textOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 75.0),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 12.5),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 12.5),
    ]).animate(_controller);

    _textTranslateY = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(12.0), weight: 75.0),
      TweenSequenceItem(tween: Tween<double>(begin: 12.0, end: 0.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 12.5),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 12.5),
    ]).animate(_controller);

    // 2.1s - 2.4s (0.875 -> 1.000): Master fade out to Home Screen
    _masterFadeOut = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 87.5),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 12.5),
    ]).animate(_controller);
  }

  void _setupAudioTriggers() {
    _controller.addListener(() {
      final double t = _controller.value;

      // 0.0s: Soft cinematic whoosh
      if (t >= 0.01 && !_whooshPlayed) {
        _whooshPlayed = true;
        AudioManager().playWhoosh();
      }

      // 0.2s - 1.8s: Subtle metallic spin feedback at each half rotation
      if (t >= 0.083 && t <= 0.73) {
        final double currentAngle = _coinRotation.value;
        final int currentHalfTurns = (currentAngle / math.pi).floor();
        if (currentHalfTurns > _spinChimesPlayed && currentHalfTurns < 5) {
          _spinChimesPlayed = currentHalfTurns;
          AudioManager().playSpin();
        }
      }

      // 1.75s - 1.8s: Reveal chime as coin completes final rotation
      if (t >= 0.73 && !_revealChimePlayed) {
        _revealChimePlayed = true;
        AudioManager().playChime();
      }
    });
  }

  Future<void> _initBackendConcurrently() async {
    final startTime = DateTime.now();
    debugPrint('SplashScreen: Concurrently initializing backend services...');

    try {
      await DBHelper().repairDatabaseIfNeeded();
    } catch (e) {
      debugPrint('SplashScreen: repairDatabaseIfNeeded error: $e');
    }

    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint('SplashScreen: NotificationService init error: $e');
    }

    try {
      AutoBackupManager().start();
    } catch (e) {
      debugPrint('SplashScreen: AutoBackupManager start error: $e');
    }

    try {
      if (mounted) {
        await context.read<LoanProvider>().loadBorrowers();
      }
    } catch (e) {
      debugPrint('SplashScreen: LoanProvider preload error: $e');
    }

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    debugPrint('SplashScreen: Backend services initialized in $elapsed ms.');

    if (mounted) {
      _backendInitialized = true;
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate({bool force = false}) {
    // Guarantee that app opens and transitions within 3 seconds
    if ((force || (_animationMinimumReached && _backendInitialized)) && !_navigated) {
      _navigated = true;
      debugPrint('SplashScreen: Transitioning smoothly to Home Screen.');
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AppLockWrapper(
            child: MainNavigationScreen(),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDark = themeProvider.isDarkMode;

    // Background colors per rules: Deep Matte Black (#090909) / Soft White (#FAFAFA)
    final Color bgColor = isDark ? const Color(0xFF090909) : const Color(0xFFFAFAFA);
    final Color radialCenterColor = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF);
    final Color textColor = isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1A1A1A);
    final Color subtextColor = isDark ? const Color(0xFF999999) : const Color(0xFF666666);

    return Scaffold(
      backgroundColor: bgColor,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: bgColor,
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color.lerp(bgColor, radialCenterColor, _bgOpacity.value)!,
                    bgColor,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: PremiumBackgroundElements(animation: _controller, isDark: isDark),
                  ),
                  // 1. Soft Elliptical Shadow underneath coin
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.5 + 85,
                    child: Opacity(
                      opacity: _shadowOpacity.value,
                      child: Transform.scale(
                        scale: _shadowScale.value,
                        child: Container(
                          width: 130,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.75 : 0.25),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Elegant Golden Glow behind Logo (at 2.2s stop point)
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.5 - 90,
                    child: Opacity(
                      opacity: _glowOpacity.value,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.55),
                              blurRadius: 45,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. The 3D Spinning Metallic Coin
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.5 - 90 + _coinTranslateY.value,
                    child: Transform.scale(
                      scale: _coinScale.value,
                      child: CoinWidget(
                        rotationAngle: _coinRotation.value,
                        size: 170,
                        isDarkTheme: isDark,
                        reflectionOffset: _coinRotation.value * 1.4 + _controller.value * 2.5,
                      ),
                    ),
                  ),

                  // 4. Typography (2.3s Text Fades In)
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.5 + 125,
                    child: Opacity(
                      opacity: _textOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _textTranslateY.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Credits',
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Smart Loan Management',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 2.2,
                                color: subtextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          );
        },
      ),
    );
  }
}
