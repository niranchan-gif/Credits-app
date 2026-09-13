import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/app_colors.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/backup_freshness_service.dart';
import '../widgets/read_only_banner.dart';
import '../services/auto_backup_manager.dart';
import '../widgets/progress_dialog.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  AppLifecycleListener? _lifecycleListener;

  final List<Widget> _pages = [
    const HomeScreen(),
    const ReportsScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _lifecycleListener = AppLifecycleListener(
        onExitRequested: () async {
          final shouldExit = await _showExitDialog(context);
          return shouldExit ? AppExitResponse.exit : AppExitResponse.cancel;
        },
      );
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<bool> _showExitDialog(BuildContext context) async {
    final shouldBackup = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup Before Exit', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Do you want to back up your latest data before closing the application?\n\nBacking up now helps keep your Google Drive backup up to date.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null), // Cancel
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // Exit Without Backup
            child: const Text('Exit Without Backup', style: TextStyle(color: AppColors.error)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), // Backup & Exit
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Backup & Exit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldBackup == null) {
      return false; // Cancel, keep app open
    }

    if (shouldBackup == false) {
      return true; // Exit immediately
    }

    // Backup & Exit flow
    final backupSuccess = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProgressDialog(
        title: 'Backup',
        successMessage: 'Backup',
        errorMessage: 'Backup Failed',
        action: (updateProgress) async {
          await AutoBackupManager().checkAndPerformBackup(
            forceManual: true,
            onProgress: (p) => updateProgress(p, ''),
          );
        },
      ),
    );

    // If backup succeeded, allow exit. Otherwise keep app open (so user sees error).
    return backupSuccess == true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_currentIndex != 0) {
              setState(() => _currentIndex = 0);
              return;
            }
            final shouldExit = await _showExitDialog(context);
            if (shouldExit) {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            extendBody: true,
            body: Column(
              children: [
                if (isReadOnly) const ReadOnlyBanner(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    child: _pages[_currentIndex],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _buildFloatingNavBar(),
          ),
        );
      },
    );
  }

  Widget _buildFloatingNavBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      height: 68,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.88)
            : AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
          width: 1,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(LucideIcons.home, "Home", 0),
              _navItem(LucideIcons.barChart3, "Reports", 1),
              _navItem(LucideIcons.settings, "Settings", 2),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 0.5, end: 0, duration: 800.ms, curve: Curves.easeOutBack);
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? AppColors.accentLight : AppColors.accent;
    final inactiveColor = isDark ? AppColors.textTertiaryDark : AppColors.textSecondary;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: isDark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: isSelected
              ? Border.all(
                  color: activeColor.withValues(alpha: isDark ? 0.35 : 0.22),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: activeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

