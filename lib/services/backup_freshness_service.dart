import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'google_drive_service.dart';
import 'json_restore_service.dart';
import 'json_backup_service.dart';
import 'google_drive_json_backup_service.dart';
import 'auto_backup_manager.dart';
import '../database/db_helper.dart';
import '../providers/loan_provider.dart';
import '../screens/main_navigation_screen.dart';
import '../main.dart'; // for navigatorKey
import '../utils/app_colors.dart';
import '../widgets/progress_dialog.dart';

class BackupFreshnessService {
  static final BackupFreshnessService _instance = BackupFreshnessService._internal();
  factory BackupFreshnessService() => _instance;
  BackupFreshnessService._internal();

  static final ValueNotifier<bool> isReadOnlyMode = ValueNotifier<bool>(false);
  static bool isAppInForeground = true;

  bool _isChecking = false;
  bool _isDialogShowing = false;

  /// Check if backups and uploads are currently blocked.
  /// Blocked only if: Google Drive is newer (is_backup_blocked == true)
  /// (provided the user is connected to Google Drive).
  Future<bool> areBackupsBlocked() async {
    final driveConnected = await GoogleDriveService().isConnected();
    if (!driveConnected) {
      return false; // Not connected: offline-first local mode, not blocked.
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_backup_blocked') ?? false;
  }

  /// Perform validation check silently. Returns true if backups are blocked.
  Future<bool> checkFreshnessSilent() async {
    await checkFreshness(silent: true);
    return await areBackupsBlocked();
  }

  /// Locate backup and compare timestamps. Shows the mandatory dialog if remote is newer.
  Future<void> checkFreshness({bool silent = false}) async {
    if (_isChecking) {
      debugPrint('BackupFreshnessService: Freshness check already in progress. Skipping.');
      return;
    }
    _isChecking = true;

    try {
      final driveService = GoogleDriveService();
      final connected = await driveService.isConnected();
      if (!connected) {
        debugPrint('BackupFreshnessService: Google Drive not connected. Clearing blocks.');
        isReadOnlyMode.value = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_backup_blocked', false);
        await prefs.setBool('last_drive_check_success', true);
        return;
      }

      // Check internet availability
      final hasInternet = await AutoBackupManager.isInternetAvailable();
      if (!hasInternet) {
        debugPrint('BackupFreshnessService: Offline. Entering Read Only Mode.');
        isReadOnlyMode.value = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('last_drive_check_success', false);
        return;
      }

      final authClient = await driveService.getAuthClient();
      final driveApi = drive.DriveApi(authClient);
      
      // Locate backups folder
      final folderId = await driveService.findOrCreateBackupsFolder(driveApi);
      
      // Locate credits_backup.json.enc
      final listResult = await driveApi.files.list(
        q: "name = 'credits_backup.json.enc' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, createdTime, size)',
      );

      final files = listResult.files;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_drive_check_timestamp', DateTime.now().toUtc().toIso8601String());

      if (files == null || files.isEmpty) {
        debugPrint('BackupFreshnessService: No credits_backup.json.enc backup file found on Google Drive.');
        isReadOnlyMode.value = false;
        await prefs.setBool('is_backup_blocked', false);
        await prefs.setBool('last_drive_check_success', true);
        return;
      }

      final driveFile = files.first;
      final driveTime = driveFile.modifiedTime ?? driveFile.createdTime;

      if (driveTime == null) {
        debugPrint('BackupFreshnessService: Backup file has no timestamp metadata.');
        isReadOnlyMode.value = false;
        await prefs.setBool('is_backup_blocked', false);
        await prefs.setBool('last_drive_check_success', true);
        return;
      }

      // Read local database last modified timestamp
      final localTimeString = prefs.getString('local_db_last_modified_timestamp');
      DateTime? localTime = localTimeString != null ? DateTime.tryParse(localTimeString) : null;

      if (localTime == null) {
        // Fallback to last successful backup timestamps
        final fallbackStr = prefs.getString('last_excel_backup_timestamp') ?? prefs.getString('last_gdrive_backup_date');
        if (fallbackStr != null) {
          localTime = DateTime.tryParse(fallbackStr);
        }
      }

      // Safe initialization for null localTime
      if (localTime == null) {
        final isEmpty = await DBHelper().isDatabaseEmpty();
        if (!isEmpty) {
          // DB has existing data but no timestamp: mark it as now to prevent false block/wipe
          localTime = DateTime.now().toUtc();
          await prefs.setString('local_db_last_modified_timestamp', localTime.toIso8601String());
        } else {
          // DB is completely empty: set to epoch 0 so it is older than remote backup
          localTime = DateTime.fromMillisecondsSinceEpoch(0).toUtc();
        }
      }

      debugPrint('BackupFreshnessService: Comparing Drive timestamp (${driveTime.toUtc()}) vs Local timestamp (${localTime.toUtc()})');

      if (driveTime.toUtc().isAfter(localTime.toUtc().add(const Duration(minutes: 2)))) {
        debugPrint('BackupFreshnessService: Google Drive backup is NEWER!');
        await prefs.setBool('is_backup_blocked', true);
        await prefs.setBool('last_drive_check_success', true);
        isReadOnlyMode.value = false; // Dialog will block user, exit read-only mode if active

        if (!silent) {
          _showNewerBackupDialog(driveFile);
        }
      } else {
        debugPrint('BackupFreshnessService: Local data is up-to-date.');
        await prefs.setBool('is_backup_blocked', false);
        await prefs.setBool('last_drive_check_success', true);
        isReadOnlyMode.value = false; // Successfully verified, exit read-only mode
      }
    } catch (e) {
      debugPrint('BackupFreshnessService Error during freshness check: $e');
      isReadOnlyMode.value = false; // Do not lock local DB on API errors or exceptions while online
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('last_drive_check_success', false);
    } finally {
      _isChecking = false;
    }
  }

  /// Show the non-dismissible newer backup found restore dialog
  void _showNewerBackupDialog(drive.File driveFile) {
    if (_isDialogShowing) return;
    
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('BackupFreshnessService Dialog aborted: No valid navigator context.');
      return;
    }

    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: _NewerBackupDialogContent(
            driveFile: driveFile,
            onRestoreComplete: () {
              _isDialogShowing = false;
            },
          ),
        );
      },
    );
  }
}

class _NewerBackupDialogContent extends StatefulWidget {
  final drive.File driveFile;
  final VoidCallback onRestoreComplete;

  const _NewerBackupDialogContent({
    required this.driveFile,
    required this.onRestoreComplete,
  });

  @override
  State<_NewerBackupDialogContent> createState() => _NewerBackupDialogContentState();
}

class _NewerBackupDialogContentState extends State<_NewerBackupDialogContent> {
  bool _isRestoring = false;
  String? _errorMessage;

  Future<void> _performRestore() async {
    setState(() {
      _isRestoring = true;
      _errorMessage = null;
    });

    File? tempFile;
    bool success = false;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ProgressDialog(
          title: 'Restoring Backup',
          successMessage: '✓ Restore Completed',
          errorMessage: 'Restore Failed',
          action: (updateProgress) async {
            final driveService = GoogleDriveService();
            
            // 1. Restore CDB Snapshot
              updateProgress(0.3, 'Downloading JSON Encrypted Backup...');
              await JsonRestoreService().restoreFromDrive(
                onProgress: (progress, message) {
                  updateProgress(progress, message);
                },
              );
  
              // 3. Update local timestamp
            final prefs = await SharedPreferences.getInstance();
            final driveTime = widget.driveFile.modifiedTime ?? widget.driveFile.createdTime ?? DateTime.now();
            await prefs.setString('local_db_last_modified_timestamp', driveTime.toUtc().toIso8601String());
            await prefs.setBool('is_backup_blocked', false);
            await prefs.setBool('last_drive_check_success', true);

            // 4. Reload borrowers in LoanProvider
            if (mounted) {
              final provider = Provider.of<LoanProvider>(context, listen: false);
              await provider.loadBorrowers();
            }

            // 5. Re-run validation (triggers checkFreshness to confirm block is removed)
            await BackupFreshnessService().checkFreshness(silent: true);
            success = true;
          },
        ),
      );

      // 6. Open the dashboard (resetting navigation stack and index to 0)
      if (success && mounted) {
        widget.onRestoreComplete();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[DialogRestore] Restore flow failed: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      setState(() {
        _isRestoring = false;
      });
      if (tempFile != null && await tempFile!.exists()) {
        try {
          await tempFile!.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      title: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Text(
            'New Data Found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A newer backup is available.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              'Error: $_errorMessage',
              style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isRestoring ? null : _performRestore,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isRestoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Restore', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
