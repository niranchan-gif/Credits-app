import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/app_colors.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../services/backup_freshness_service.dart';
import '../widgets/read_only_banner.dart';
import '../services/auto_backup_manager.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_keyboard/app_keyboard.dart';

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
        backgroundColor: Theme.of(context).colorScheme.surface,
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
    if (!context.mounted) return false;
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
            if (AppKeyboardController.instance.isVisible) {
              AppKeyboardController.instance.hide();
              return;
            }
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
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _pages,
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

    return GlassCard(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      borderRadius: 32,
      blur: 35,
      color: isDark
          ? Colors.black.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.75),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.08),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withValues(alpha: 0.4) : const Color(0xFF0F172A).withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
      child: SizedBox(
        height: 68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / 3;
            return Stack(
              children: [
                // Sliding Water Glass Pill
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  left: _currentIndex * tabWidth,
                  top: 0,
                  bottom: 0,
                  width: tabWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: isDark ? 0.2 : 0.6),
                                Colors.white.withValues(alpha: isDark ? 0.05 : 0.15),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.9),
                                blurRadius: 10,
                                spreadRadius: -5,
                                offset: const Offset(0, -5),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withValues(alpha: isDark ? 0.3 : 0.9),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Icons and Labels
                Row(
                  children: [
                    _navItem(LucideIcons.home, "Home", 0, tabWidth),
                    _navItem(LucideIcons.barChart3, "Reports", 1, tabWidth),
                    _navItem(LucideIcons.settings, "Settings", 2, tabWidth),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index, double width) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? AppColors.accentLight : AppColors.accent;
    final inactiveColor = isDark ? AppColors.textTertiaryDark : AppColors.textSecondary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 22,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: isSelected
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                      )
                    : const SizedBox(width: 0, height: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


