import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../database/db_helper.dart';
import '../../services/notification_service.dart';
import '../../services/auto_backup_manager.dart';
import '../../services/google_drive_service.dart';
import '../../providers/loan_provider.dart';
import '../app_lock_wrapper.dart';
import '../auth/sign_in_screen.dart';
import '../main_navigation_screen.dart';

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

  // Background color matching the logo's bottom right depth
  final Color _bgColor = const Color(0xFF021711);

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
      duration: const Duration(milliseconds: 3500)
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
      // FIXED: Start immediately at 0.0 instead of 0.1 to avoid the initial "lag/stuck" perception
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65))
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
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65))
    );

    // 9 * pi = 4.5 spins.
    _spinAnim = Tween<double>(begin: 0, end: 9 * math.pi).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.65, curve: Curves.easeInOutCubic))
    );

    _textFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeIn))
    );

    _textScaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeOutBack))
    );
    
    _letterSpacingAnim = Tween<double>(begin: 20.0, end: 6.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.68, 0.9, curve: Curves.easeOutCubic))
    );

    _animController.forward();

    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        _animationMinimumReached = true;
        _checkAndNavigate();
      }
    });

    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && !_navigated) {
        _checkAndNavigate(force: true);
      }
    });

    // OPTIMIZATION: Delay backend initialization significantly (2200ms) so it doesn't block the UI thread during the crucial initial coin toss.
    // By 2200ms, the coin has finished the complex physics and is resting, making any isolate stutters unnoticeable.
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _initBackendConcurrently();
      }
    });
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
      _isSignedIn = await GoogleDriveService().isConnected();
    } catch (e) {
      _isSignedIn = false;
    }
    await Future.delayed(const Duration(milliseconds: 10)); // Yield to UI thread

    try {
      await DBHelper().repairDatabaseIfNeeded();
    } catch (e) {}
    await Future.delayed(const Duration(milliseconds: 10)); // Yield to UI thread

    try {
      await NotificationService().init();
    } catch (e) {}
    await Future.delayed(const Duration(milliseconds: 10)); // Yield to UI thread

    try {
      AutoBackupManager().start();
    } catch (e) {}

    if (_isSignedIn) {
      await Future.delayed(const Duration(milliseconds: 10)); // Yield to UI thread
      try {
        if (mounted) {
          await context.read<LoanProvider>().loadBorrowers();
        }
      } catch (e) {}
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
      Widget nextScreen = _isSignedIn 
          ? const AppLockWrapper(child: MainNavigationScreen())
          : const SignInScreen();
          
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
      body: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final angle = _spinAnim.value;

          return Stack(
            children: [
              // Premium Top Light, Grid, and Data Streams
              Positioned.fill(
                child: CustomPaint(
                  painter: _PremiumBackdropPainter(_animController.value),
                ),
              ),

              // Premium Bargraph Shadow anchored to the absolute bottom (Now 4 bars)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildShadowBar(height: 100 * _getBarProgress(0, _animController.value), opacity: _getBarProgress(0, _animController.value)),
                    const SizedBox(width: 25),
                    _buildShadowBar(height: 160 * _getBarProgress(1, _animController.value), opacity: _getBarProgress(1, _animController.value)),
                    const SizedBox(width: 25),
                    _buildShadowBar(height: 240 * _getBarProgress(2, _animController.value), opacity: _getBarProgress(2, _animController.value)),
                    const SizedBox(width: 25),
                    _buildShadowBar(height: 320 * _getBarProgress(3, _animController.value), opacity: _getBarProgress(3, _animController.value)),
                  ],
                ),
              ),
              
              // Main Content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // OPTIMIZATION: Highly performant RadialGradient for aura (0 blur cost)
                        Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFF13A383).withOpacity(0.35 * _textFadeAnim.value),
                                const Color(0xFF13A383).withOpacity(0.0),
                              ],
                              stops: const [0.0, 1.0],
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
                    
                    // FIXED: Transform.translate physically pulls the text up by 40 pixels 
                    // to completely bypass the 250x250 aura container spacing
                    Transform.translate(
                      offset: const Offset(0, -40),
                      child: Transform.scale(
                        scale: _textScaleAnim.value,
                        child: Text(
                          'Credits',
                          style: GoogleFonts.leagueSpartan(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.9 * _textFadeAnim.value),
                            letterSpacing: _letterSpacingAnim.value * 0.5,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF13A383).withOpacity(0.5 * _textFadeAnim.value),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
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
    );
  }

  double _getBarProgress(int index, double progress) {
    // 3.5s total animation timeline.
    // The 4 bars must all finish before progress reaches ~0.95 so they can be seen
    // fully formed before the page transition triggers at 1.0 (3500ms).
    double duration = 0.30; // Each bar takes 30% of the total time to rise
    double start = index * (0.65 / 3.0); // Stagger starts: 0.0, ~0.21, ~0.43, ~0.65
    double end = start + duration; // 4th bar ends at 0.65 + 0.30 = 0.95
    
    if (progress <= start) return 0.0;
    if (progress >= end) return 1.0;
    
    double t = (progress - start) / (end - start);
    return Curves.easeOutBack.transform(t); // Gives a nice bouncy rise
  }

  Widget _buildShadowBar({required double height, required double opacity}) {
    // Clamp opacity since Curves.easeOutBack can overshoot past 1.0
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
            const Color(0xFF063628).withOpacity(safeOpacity), 
            const Color(0xFF021711).withOpacity(0.2 * safeOpacity),
          ],
        ),
      ),
    );
  }

  Widget _buildCoin(double angle) {
    final isFront = math.cos(angle) > 0;

    return Transform(
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
    );
  }

  Widget _buildGlassyFace({required Widget child, required double angle}) {
    const double coinSize = 160.0;
    
    // Calculate a sweep value from -1.0 to 1.0 based on rotation
    final double sweep = math.sin(angle * 1.5);

    return Container(
      width: coinSize,
      height: coinSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // OPTIMIZATION: LinearGradient is completely hardware accelerated on all mobile GPUs
        // SweepGradient causes severe software rendering lag on many Android devices
        gradient: const LinearGradient(
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
        // OPTIMIZATION: Completely removed BoxShadows under 3D transforms to fix lag!
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0), // Thicker substantial gold rim
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Glass core gradient (Pure Emerald, no gold bleed)
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
              color: Colors.white.withOpacity(0.2), // Faint white glass reflection only
              width: 1.0,
            ),
            // OPTIMIZATION: Completely removed BoxShadows under 3D transforms to fix lag!
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              child, // Logo or Rupee symbol

              // Glassy top highlight arc
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: coinSize * 0.45,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(coinSize / 2)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.6),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // OPTIMIZATION: Highly performant GPU sweep using Transform.translate instead of animated Gradient Alignment
              ClipOval(
                child: Transform.translate(
                  offset: Offset(sweep * coinSize * 1.5, 0),
                  child: Container(
                    width: coinSize * 1.5,
                    height: coinSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.0),
                          Colors.white.withOpacity(0.5), // Specular shine
                          Colors.white.withOpacity(0.0),
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
          // OPTIMIZATION: Removed expensive text shadows from the 3D rotating object
        ),
      ),
    );
  }

  Widget _buildLogoSide(double angle) {
    return _buildGlassyFace(
      angle: angle,
      child: Transform.translate(
        offset: const Offset(0.0, 0.0), 
        child: ClipOval(
          child: Image.asset(
            'assets/icon/app_icon.png',
            fit: BoxFit.cover,
            width: 120, 
            height: 120,
          ),
        ),
      ),
    );
  }
}

class _PremiumBackdropPainter extends CustomPainter {
  final double animationValue;

  _PremiumBackdropPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Top Ambient Spotlight Flare
    final topLightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -1.0), // Anchored at top center
        radius: 1.5,
        colors: [
          const Color(0xFF13A383).withOpacity(0.25 + 0.05 * math.sin(animationValue * math.pi * 2)), // Subtle pulse
          const Color(0xFF096853).withOpacity(0.1),
          const Color(0xFF021711).withOpacity(0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), topLightPaint);

    // 2. Premium Tech Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF13A383).withOpacity(0.08)
      ..strokeWidth = 1.0;
      
    const double spacing = 35.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // 3. Cinematic Bokeh / Floating Glass Dust (Ultra-premium organic particles)
    final random = math.Random(42); // Fixed seed
    for (int i = 0; i < 15; i++) {
      double startX = random.nextDouble() * size.width;
      double startY = random.nextDouble() * size.height;
      
      // Slow drift
      double driftY = startY - (animationValue * 40 * (random.nextDouble() + 0.5));
      if (driftY < -50) driftY += size.height + 100;
      
      double driftX = startX + math.sin(animationValue * math.pi * 2 + i) * 30;
      
      // Create large, very soft blurred circles that fade in and out (twinkle)
      double radius = 10.0 + random.nextDouble() * 30.0;
      double twinkle = (0.5 + 0.5 * math.sin(animationValue * math.pi * 4 + i)).clamp(0.0, 1.0);
      
      // Alternate between mint green and subtle gold
      Color baseColor = i % 4 == 0 ? const Color(0xFFFFDF73) : const Color(0xFF13A383);
      
      final bokehPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            baseColor.withOpacity(0.15 * twinkle),
            baseColor.withOpacity(0.05 * twinkle),
            baseColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(driftX, driftY), radius: radius));
        
      canvas.drawCircle(Offset(driftX, driftY), radius, bokehPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumBackdropPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

