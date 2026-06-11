import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../services/backup_freshness_service.dart';
import 'app_lock_screen.dart';

class AppLockWrapper extends StatefulWidget {
  final Widget child;

  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper> with WidgetsBindingObserver {
  final _authService = AuthService();
  bool _isLocked = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BackupFreshnessService.isAppInForeground = true;
      if (!_isLocked) {
        BackupFreshnessService().checkFreshness();
      }
    } else if (state == AppLifecycleState.paused || 
               state == AppLifecycleState.inactive || 
               state == AppLifecycleState.detached) {
      BackupFreshnessService.isAppInForeground = false;
    }

    // Lock the app when it goes to the background (paused).
    // Doing this on 'resumed' causes an infinite loop because the OS biometric prompt 
    // triggers 'paused' and then 'resumed' when it closes.
    if (state == AppLifecycleState.paused) {
      _checkLockStatus();
    }
  }

  Future<void> _checkLockStatus() async {
    try {
      debugPrint("AppLockWrapper: Checking lock status...");
      final enabled = await _authService.isLockEnabled();
      debugPrint("AppLockWrapper: Lock enabled: $enabled");
      if (enabled && !_isLocked) {
        setState(() => _isLocked = true);
      } else if (!enabled) {
        // App Lock is disabled, check freshness on cold start
        WidgetsBinding.instance.addPostFrameCallback((_) {
          BackupFreshnessService().checkFreshness();
        });
      }
    } catch (e, stack) {
      debugPrint("AppLockWrapper: Error checking lock status: $e\n$stack");
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _onUnlocked() {
    setState(() => _isLocked = false);
    // Check freshness on unlock
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackupFreshnessService().checkFreshness();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) return const Scaffold(backgroundColor: Color(0xFF1E3A5F));
    if (_isLocked) return AppLockScreen(onUnlocked: _onUnlocked);
    return widget.child;
  }
}

