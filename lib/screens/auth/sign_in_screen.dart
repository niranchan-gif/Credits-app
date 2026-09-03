import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart';
import '../../providers/loan_provider.dart';
import '../../database/db_helper.dart';
import '../../services/google_drive_service.dart';
import '../../services/google_drive_excel_backup_service.dart';
import '../../services/excel_backup_service.dart';
import '../../utils/app_colors.dart';
import '../app_lock_wrapper.dart';
import '../main_navigation_screen.dart';
import '../../widgets/progress_dialog.dart';

/// Sign-in / Registration screen for the Credits app.
/// Shown when the user is not signed in or has no account registered.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with TickerProviderStateMixin {
  
  bool _isLoading = false;
  String? _errorMessage;

  // Animations
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;
  late Animation<double> _bgAnim;

  // Zoom Transition
  late AnimationController _zoomController;
  late Animation<double> _zoomAnim;
  bool _isZooming = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _bgAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _zoomAnim = Tween<double>(begin: 1.0, end: 60.0).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeInOutExpo),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final driveService = GoogleDriveService();
      final account = await driveService.connectAccount();

      if (account == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign in aborted.';
        });
        return;
      }

      if (mounted) {
        HapticFeedback.lightImpact();
      }

      // Switch to the account's specific local database
      await DBHelper().switchDatabase();

      // Check for backups and restore if any
      await _checkAndRestoreBackup(driveService);

    } catch (e) {
      debugPrint('SignIn error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred during sign in. Please try again.';
        });
      }
    }
  }

  Future<void> _checkAndRestoreBackup(GoogleDriveService driveService) async {
    bool restoreSuccess = false;
    
    // We do this in a ProgressDialog to keep the user informed
    if (!mounted) return;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Checking for backups...',
        successMessage: '✓ Ready',
        errorMessage: 'Restore Failed',
        action: (updateProgress) async {
          updateProgress(0.1, 'Checking Google Drive for backups...');
          
          try {
            await GoogleDriveExcelBackupService().initializeOnStartup();
          } catch (e) {
             debugPrint('Failed to initialize Google Drive Excel Backup Service on sign in: $e');
          }
          
          final backups = await driveService.listBackups();
          
          if (backups.isEmpty) {
            updateProgress(1.0, 'No backups found on Drive. Using local data.');
            if (mounted) {
              await context.read<LoanProvider>().loadBorrowers();
            }
            restoreSuccess = true;
            return;
          }

          updateProgress(0.2, 'Found latest backup. Downloading...');
          final latestBackup = backups.first;
          final fileId = latestBackup['id'] as String;

          final bytes = await driveService.downloadBackup(
            fileId,
            onProgress: (p) => updateProgress(0.2 + p * 0.4, 'Downloading backup data...'),
          );

          updateProgress(0.7, 'Restoring data locally...');
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/restore_temp.xlsx');
          await tempFile.writeAsBytes(bytes, flush: true);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('google_drive_excel_backup_file_id', fileId);

          await ExcelBackupService.importBackup(
            tempFile.path,
            merge: false, // Replace completely
            onProgress: (p) => updateProgress(0.7 + p * 0.2, 'Applying backup to database...'),
          );

          if (mounted) {
            await context.read<LoanProvider>().loadBorrowers();
          }
          
          if (await tempFile.exists()) {
             try { await tempFile.delete(); } catch (_) {}
          }

          updateProgress(1.0, 'Data restored successfully!');
          restoreSuccess = true;
        },
      ),
    );

    if (restoreSuccess && mounted) {
      setState(() {
        _isZooming = true;
      });
      // Start zoom but DO NOT await it.
      _zoomController.forward();
      
      // Delay slightly to let the green flood the screen, then overlap the route transition
      // so that Flutter's page building logic happens seamlessly underneath.
      await Future.delayed(const Duration(milliseconds: 350));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AppLockWrapper(child: MainNavigationScreen()),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final size = MediaQuery.of(context).size;

    final bgColor = isDark ? const Color(0xFF111714) : const Color(0xFFF0F5F2);
    final cardColor = isDark ? const Color(0xFF1C2420) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1A2A22);
    final subtextColor = isDark ? const Color(0xFF8FA89A) : const Color(0xFF5A7A68);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Decorative background ──────────────────────────────────────
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _SignInBackgroundPainter(
                progress: _bgAnim.value,
                isDark: isDark,
              ),
            ),
          ),

          // ── Radial glow top-right ──────────────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.6,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withOpacity(isDark ? 0.25 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Radial glow bottom-left ────────────────────────────────────
          Positioned(
            bottom: -80,
            left: -40,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.5,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.secondary.withOpacity(isDark ? 0.2 : 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnim.value,
                    child: Transform.translate(
                      offset: Offset(0, _slideAnim.value),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Logo ──────────────────────────────────────────
                      _buildLogo(isDark),
                      
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isZooming ? 0.0 : 1.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 48),

                            // ── Card ──────────────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(isDark ? 0.18 : 0.12),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Colors.white.withOpacity(isDark ? 0.08 : 0.04),
                              blurRadius: 60,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Title
                            Text(
                              'Sign In',
                              style: GoogleFonts.outfit(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                letterSpacing: 0.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in with your Google Account to automatically restore your backups.',
                              style: GoogleFonts.outfit(
                                fontSize: 13.5,
                                color: subtextColor,
                                fontWeight: FontWeight.w400,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),

                            // Error message
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.error.withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                        color: AppColors.error, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: AppColors.error,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Submit button
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _handleGoogleSignIn,
                                icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(LucideIcons.chrome, color: Colors.white, size: 20),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                label: Text(
                                  _isLoading ? 'Signing In...' : 'Sign In with Google',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── Security note ─────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 14, color: subtextColor.withOpacity(0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Your data is securely backed up to your Google Drive',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: subtextColor.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ],
),
);
}

  Widget _buildLogo(bool isDark) {
    return Column(
      children: [
        ScaleTransition(
          scale: _zoomAnim,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/icon/app_icon.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                  AnimatedBuilder(
                    animation: _zoomAnim,
                    builder: (_, __) {
                      // Fade in the green color as the logo zooms.
                      // _zoomAnim goes from 1.0 to 60.0.
                      // Start fading at scale 2.0, completely green by scale 15.0
                      final opacity = ((_zoomAnim.value - 2.0) / 13.0).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Container(
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _isZooming ? 0.0 : 1.0,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text(
                'Credits',
                style: GoogleFonts.outfit(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1A2A22),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Smart Loan Management',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.0,
                  color: isDark ? const Color(0xFF8FA89A) : const Color(0xFF5A7A68),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Decorative background painter for the sign-in screen
class _SignInBackgroundPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _SignInBackgroundPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;

    // Subtle geometric circles
    paint.color = (isDark
            ? const Color(0xFF285A48)
            : const Color(0xFF285A48))
        .withOpacity(0.06 * progress);
    paint.strokeWidth = 1;
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.08), 160, paint);

    paint.color = (isDark
            ? const Color(0xFFDAA464)
            : const Color(0xFFDAA464))
        .withOpacity(0.05 * progress);
    paint.strokeWidth = 0.8;
    canvas.drawCircle(
        Offset(size.width * 0.05, size.height * 0.95), 180, paint);

    paint.color = const Color(0xFF285A48).withOpacity(0.04 * progress);
    paint.strokeWidth = 1.2;
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.5), 300, paint);

    // Grid dots
    const double spacing = 40.0;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        final dx = x - size.width / 2;
        final dy = y - size.height / 2;
        final dist = math.sqrt(dx * dx + dy * dy);
        final maxDist = size.width;
        double alpha = (1.0 - dist / maxDist).clamp(0.0, 1.0);
        alpha = alpha * 0.08 * progress;
        if (alpha > 0) {
          dotPaint.color = (isDark ? Colors.white : const Color(0xFF285A48))
              .withOpacity(alpha);
          canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignInBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
