import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:googleapis/drive/v3.dart' as drive;
import '../../providers/theme_provider.dart';
import '../../providers/loan_provider.dart';
import '../../database/db_helper.dart';
import '../../services/google_drive_service.dart';
import '../../services/json_restore_service.dart';
import '../../services/google_drive_json_backup_service.dart';
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
        successMessage: 'Ready',
        errorMessage: 'Restore Failed',
        action: (updateProgress) async {
          updateProgress(0.1, 'Checking Google Drive for backups...');
          
          final isDbEmpty = await DBHelper().isDatabaseEmpty();
          final authClient = await driveService.getAuthClient();
          final driveApi = drive.DriveApi(authClient);

          // Locate backups folder
          final folderResult = await driveApi.files.list(
            q: "name = '${GoogleDriveJsonBackupService.backupFolderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
            spaces: 'drive',
            $fields: 'files(id)',
          );

          drive.File? backupFile;
          if (folderResult.files != null && folderResult.files!.isNotEmpty) {
            final folderId = folderResult.files!.first.id!;
            final fileList = await driveApi.files.list(
              q: "parents in '$folderId' and name='${GoogleDriveJsonBackupService.backupFileName}' and trashed=false",
              spaces: 'drive',
              $fields: 'files(id, name, modifiedTime, createdTime)',
            );
            if (fileList.files != null && fileList.files!.isNotEmpty) {
              backupFile = fileList.files!.first;
            }
          }

          final prefs = await SharedPreferences.getInstance();

          if (backupFile == null) {
            updateProgress(1.0, 'No cloud backups found. Using local data.');
            if (mounted) {
              await context.read<LoanProvider>().loadBorrowers();
            }
            restoreSuccess = true;
            return;
          }

          final driveTime = backupFile.modifiedTime ?? backupFile.createdTime ?? DateTime.now();
          final localTimeString = prefs.getString('local_db_last_modified_timestamp');
          final localTime = localTimeString != null ? DateTime.tryParse(localTimeString) : null;

          bool shouldRestore = false;
          if (isDbEmpty) {
            // Local DB has no data: fresh login or new device, restore needed!
            shouldRestore = true;
          } else if (localTime != null && driveTime.toUtc().isAfter(localTime.toUtc().add(const Duration(minutes: 2)))) {
            // Remote cloud backup is strictly newer than local modifications
            shouldRestore = true;
          }

          if (!shouldRestore) {
            updateProgress(1.0, 'Local data is up to date.');
            if (mounted) {
              await context.read<LoanProvider>().loadBorrowers();
            }
            restoreSuccess = true;
            return;
          }

          updateProgress(0.3, 'Restoring backup from Google Drive...');
          await JsonRestoreService().restoreFromDrive(
            onProgress: (p, msg) => updateProgress(0.3 + p * 0.6, msg),
          );

          await prefs.setString('local_db_last_modified_timestamp', driveTime.toUtc().toIso8601String());
          await prefs.setBool('is_backup_blocked', false);
          await prefs.setBool('last_drive_check_success', true);

          if (mounted) {
            await context.read<LoanProvider>().loadBorrowers();
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

    final bgColor = isDark ? const Color(0xFF111714) : const Color(0xFFF2F6F4);
    final cardColor = isDark ? const Color(0xFF1A231F) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF3F5F4) : const Color(0xFF15221B);
    final subtextColor = isDark ? const Color(0xFF8FA89A) : const Color(0xFF5A7A68);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Background covered with geometric elements ─────────────────
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

          // ── Radial glow top-right (Emerald) ────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.7,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: isDark ? 0.22 : 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Radial glow top-left (Warm Gold / Amber) ───────────────────
          Positioned(
            top: -50,
            left: -50,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.45,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFDAA464).withValues(alpha: isDark ? 0.16 : 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Radial glow bottom-left (Teal / Secondary) ─────────────────
          Positioned(
            bottom: -80,
            left: -50,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.5,
                child: Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.secondary.withValues(alpha: isDark ? 0.18 : 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Radial glow bottom-right (Mint) ────────────────────────────
          Positioned(
            bottom: -60,
            right: -60,
            child: AnimatedBuilder(
              animation: _fadeAnim,
              builder: (_, __) => Opacity(
                opacity: _fadeAnim.value * 0.4,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF2DD4BF).withValues(alpha: isDark ? 0.15 : 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Main content (Minimal & Balanced) ──────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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
                      // ── Logo without extra text or background ─────────
                      _buildLogo(isDark),

                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isZooming ? 0.0 : 1.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 28),

                            // ── Minimal Sign In Card ─────────────────────
                            Container(
                              constraints: const BoxConstraints(maxWidth: 400),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : const Color(0xFF285A48).withValues(alpha: 0.08),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                                    blurRadius: 36,
                                    offset: const Offset(0, 14),
                                  ),
                                  BoxShadow(
                                    color: (isDark ? Colors.white : AppColors.accent)
                                        .withValues(alpha: isDark ? 0.03 : 0.02),
                                    blurRadius: 1,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Title
                                  Text(
                                    'Sign In',
                                    style: GoogleFonts.outfit(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Connect your Google Account to automatically sync and safeguard your loan records.',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13.5,
                                      color: subtextColor,
                                      fontWeight: FontWeight.w400,
                                      height: 1.45,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 28),

                                  // Error message
                                  if (_errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.error.withValues(alpha: 0.25),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline_rounded,
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
                                    const SizedBox(height: 20),
                                  ],

                                  // Submit button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            AppColors.accent.withValues(alpha: 0.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    LucideIcons.chrome,
                                                    color: Color(0xFF1A73E8),
                                                    size: 16,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Continue with Google',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 15.5,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Security footer (overflow-safe) ──────────
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.lock,
                                    size: 12.5,
                                    color: subtextColor.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Encrypted • Private Google Drive storage',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: subtextColor.withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
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
    return ScaleTransition(
      scale: _zoomAnim,
      child: Image.asset(
        'assets/icon/logo.png',
        height: 100,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Decorative background painter covered with subtle geometric elements
class _SignInBackgroundPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _SignInBackgroundPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeColor = (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF285A48))
        .withValues(alpha: 0.07 * progress);
    final goldColor = const Color(0xFFDAA464).withValues(alpha: 0.06 * progress);
    final accentColor = (isDark ? const Color(0xFF10B981) : const Color(0xFF285A48))
        .withValues(alpha: 0.07 * progress);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Concentric ripple rings across the corners & background
    // Top-right rings
    strokePaint.color = strokeColor;
    canvas.drawCircle(Offset(size.width * 0.90, size.height * 0.08), 45, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.90, size.height * 0.08), 90, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.90, size.height * 0.08), 150, strokePaint);

    // Top-left rings
    strokePaint.color = goldColor;
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.12), 40, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.12), 85, strokePaint);

    // Bottom-left rings
    strokePaint.color = strokeColor;
    canvas.drawCircle(Offset(size.width * 0.10, size.height * 0.92), 55, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.10, size.height * 0.92), 110, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.10, size.height * 0.92), 180, strokePaint);

    // Bottom-right rings
    strokePaint.color = goldColor;
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.88), 60, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.88), 120, strokePaint);

    // 2. Smooth wavy financial contours crossing the background
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = accentColor;

    final path1 = Path()
      ..moveTo(0, size.height * 0.28)
      ..cubicTo(
        size.width * 0.35, size.height * 0.22,
        size.width * 0.65, size.height * 0.34,
        size.width, size.height * 0.26,
      );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.30, size.height * 0.78,
        size.width * 0.70, size.height * 0.66,
        size.width, size.height * 0.74,
      );
    canvas.drawPath(path2, wavePaint);

    // 3. Floating geometric diamond shapes across the canvas
    _drawDiamond(canvas, Offset(size.width * 0.16, size.height * 0.36), 9, strokePaint);
    _drawDiamond(canvas, Offset(size.width * 0.85, size.height * 0.40), 11, strokePaint);
    _drawDiamond(canvas, Offset(size.width * 0.18, size.height * 0.62), 10, strokePaint);
    _drawDiamond(canvas, Offset(size.width * 0.84, size.height * 0.66), 12, strokePaint);

    // Small floating outline circles
    canvas.drawCircle(Offset(size.width * 0.82, size.height * 0.22), 7, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.14, size.height * 0.48), 6, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.54), 6, strokePaint);
    canvas.drawCircle(Offset(size.width * 0.24, size.height * 0.80), 8, strokePaint);

    // 4. Subtle plus (+) cross markers scattered across background
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = (isDark ? Colors.white : const Color(0xFF285A48))
          .withValues(alpha: 0.12 * progress);
    _drawCross(canvas, Offset(size.width * 0.14, size.height * 0.20), 4.5, crossPaint);
    _drawCross(canvas, Offset(size.width * 0.86, size.height * 0.30), 4.5, crossPaint);
    _drawCross(canvas, Offset(size.width * 0.12, size.height * 0.70), 4.5, crossPaint);
    _drawCross(canvas, Offset(size.width * 0.84, size.height * 0.76), 4.5, crossPaint);
    _drawCross(canvas, Offset(size.width * 0.50, size.height * 0.08), 4.0, crossPaint);
    _drawCross(canvas, Offset(size.width * 0.50, size.height * 0.94), 4.0, crossPaint);

    // 5. Full-canvas dot matrix grid
    const double spacing = 32.0;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final maxDist = size.width * 1.1;

    for (double x = 0; x <= size.width; x += spacing) {
      for (double y = 0; y <= size.height; y += spacing) {
        final dist = (Offset(x, y) - center).distance;
        double alpha = (1.0 - (dist / maxDist) * 0.4).clamp(0.0, 1.0);
        alpha = alpha * (isDark ? 0.06 : 0.04) * progress;
        if (alpha > 0.005) {
          dotPaint.color = (isDark ? Colors.white : const Color(0xFF285A48))
              .withValues(alpha: alpha);
          canvas.drawCircle(Offset(x, y), 0.85, dotPaint);
        }
      }
    }
  }

  void _drawCross(Canvas canvas, Offset center, double s, Paint paint) {
    canvas.drawLine(Offset(center.dx - s, center.dy), Offset(center.dx + s, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - s), Offset(center.dx, center.dy + s), paint);
  }

  void _drawDiamond(Canvas canvas, Offset center, double s, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - s)
      ..lineTo(center.dx + s, center.dy)
      ..lineTo(center.dx, center.dy + s)
      ..lineTo(center.dx - s, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignInBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
