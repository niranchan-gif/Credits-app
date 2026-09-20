import 'dart:io';
import 'dart:ui' as dart_ui;
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
import '../../widgets/glass_card.dart';
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
                                        // ── Professional Fintech Background ─────────────────
          Positioned.fill(
            child: Stack(
                children: [
                  // Base background
                  Positioned.fill(
                    child: Container(
                      color: isDark ? const Color(0xFF0A0F0D) : const Color(0xFFF4F7F5),
                    ),
                  ),
                  
                  // ── Soft Glowing Orb 1 (Top Right) ──
                  Positioned(
                    top: -150,
                    right: -100,
                    child: AnimatedBuilder(
                      animation: _fadeAnim,
                      builder: (_, __) => Opacity(
                        opacity: _fadeAnim.value * 0.8,
                        child: Container(
                          width: 500,
                          height: 500,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.accent.withValues(alpha: isDark ? 0.25 : 0.4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Soft Glowing Orb 2 (Bottom Left) ──
                  Positioned(
                    bottom: -150,
                    left: -100,
                    child: AnimatedBuilder(
                      animation: _fadeAnim,
                      builder: (_, __) => Opacity(
                        opacity: _fadeAnim.value * 0.8,
                        child: Container(
                          width: 600,
                          height: 600,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.secondary.withValues(alpha: isDark ? 0.2 : 0.35),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Scattered Finance Elements ──
                  Positioned.fill(
                    child: _buildScatteredElements(size: size, isDark: isDark),
                  ),
                ],
              ),
          ),

          // ── Main content (Minimal & Balanced) ──────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (_, child) => Transform.translate(
                      offset: Offset(0, _slideAnim.value),
                      child: child,
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _isZooming ? 0.0 : 1.0,
                    child: GlassCard(
                      margin: EdgeInsets.zero,
                      borderRadius: 32,
                      blur: 30, // Extremely clear blur
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.05) // Ultra high transparency
                          : Colors.white.withValues(alpha: 0.10), // Ultra high transparency
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.40),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ── Logo ──
                          _buildLogo(isDark),
                          const SizedBox(height: 24),
                          
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
                                  const SizedBox(height: 32),

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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScatteredElements({required Size size, required bool isDark}) {
    final icons = [
      LucideIcons.indianRupee,
      LucideIcons.creditCard,
      LucideIcons.wallet,
      LucideIcons.pieChart,
      LucideIcons.trendingUp,
      LucideIcons.shieldCheck,
      LucideIcons.percent,
      LucideIcons.piggyBank,
      LucideIcons.fileText,
      LucideIcons.landmark,
      LucideIcons.coins,
      LucideIcons.banknote,
    ];

    // Pre-defined random-looking positions and properties for a stable layout
    final positions = [
      {'x': 0.1, 'y': 0.1, 'size': 80.0, 'angle': 0.2, 'opacity': 0.15, 'icon': 0, 'speed': 0.5},
      {'x': 0.8, 'y': 0.15, 'size': 120.0, 'angle': -0.3, 'opacity': 0.1, 'icon': 1, 'speed': -0.4},
      {'x': 0.2, 'y': 0.3, 'size': 60.0, 'angle': 0.5, 'opacity': 0.12, 'icon': 2, 'speed': 0.3},
      {'x': 0.85, 'y': 0.4, 'size': 90.0, 'angle': -0.1, 'opacity': 0.1, 'icon': 3, 'speed': -0.6},
      {'x': 0.15, 'y': 0.6, 'size': 140.0, 'angle': 0.4, 'opacity': 0.08, 'icon': 4, 'speed': 0.7},
      {'x': 0.75, 'y': 0.7, 'size': 70.0, 'angle': -0.5, 'opacity': 0.15, 'icon': 5, 'speed': -0.5},
      {'x': 0.3, 'y': 0.85, 'size': 110.0, 'angle': 0.1, 'opacity': 0.1, 'icon': 6, 'speed': 0.4},
      {'x': 0.9, 'y': 0.85, 'size': 85.0, 'angle': -0.2, 'opacity': 0.12, 'icon': 7, 'speed': -0.3},
      {'x': 0.5, 'y': 0.05, 'size': 65.0, 'angle': 0.6, 'opacity': 0.09, 'icon': 8, 'speed': 0.6},
      {'x': 0.05, 'y': 0.45, 'size': 95.0, 'angle': -0.4, 'opacity': 0.11, 'icon': 9, 'speed': -0.7},
      {'x': 0.55, 'y': 0.95, 'size': 75.0, 'angle': 0.3, 'opacity': 0.14, 'icon': 10, 'speed': 0.5},
      {'x': 0.95, 'y': 0.55, 'size': 130.0, 'angle': -0.6, 'opacity': 0.07, 'icon': 11, 'speed': -0.4},
    ];

    return Stack(
      children: positions.map((pos) {
        return Positioned(
          left: size.width * (pos['x'] as double) - ((pos['size'] as double) / 2),
          top: size.height * (pos['y'] as double) - ((pos['size'] as double) / 2),
          child: AnimatedBuilder(
            animation: _slideAnim,
            builder: (context, child) {
              final speed = pos['speed'] as double;
              return Transform.translate(
                offset: Offset(0, _slideAnim.value * speed),
                child: Transform.rotate(
                  angle: (pos['angle'] as double) + (_slideAnim.value * 0.01 * speed),
                  child: Opacity(
                    opacity: pos['opacity'] as double,
                    child: Icon(
                      icons[pos['icon'] as int],
                      size: pos['size'] as double,
                      color: isDark ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }).toList(),
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
