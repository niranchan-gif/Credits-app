import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
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
        successMessage: '✓ Backup Completed',
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
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity( 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity( 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity( 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(HugeIcons.strokeRoundedHome01, "Home", 0),
              _navItem(HugeIcons.strokeRoundedBarChart, "Reports", 1),
              _navItem(HugeIcons.strokeRoundedSettings01, "Settings", 2),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 0.5, end: 0, duration: 800.ms, curve: Curves.easeOutBack);
  }

  Widget _navItem(dynamic icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withOpacity( 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.accent : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

