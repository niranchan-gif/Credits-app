import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'google_drive_service.dart';
import 'backup_service.dart';
import 'notification_service.dart';
import 'google_drive_excel_backup_service.dart';
import '../database/db_helper.dart';
import 'backup_freshness_service.dart';

enum SyncStatus {
  synced,
  syncing,
  waitingForInternet,
  failed,
  reconnect,
}

class AutoBackupManager {
  static final AutoBackupManager _instance = AutoBackupManager._internal();
  factory AutoBackupManager() => _instance;
  AutoBackupManager._internal();

  final GoogleDriveService _driveService = GoogleDriveService();
  final NotificationService _notificationService = NotificationService();
  
  Timer? _backgroundTimer;
  static Timer? _syncDebounce;
  bool _isBackingUp = false;
  
  // Broadcast notifier for other screens to listen to sync status changes
  static final ValueNotifier<SyncStatus> syncStatus = ValueNotifier<SyncStatus>(SyncStatus.synced);
  
  // Callback when a background backup completes successfully (useful to refresh UI)
  VoidCallback? onBackupCompleted;

  /// Helper function to check if active internet connection is available
  static Future<bool> isInternetAvailable() async {

    try {
      final result = await InternetAddress.lookup('clients3.google.com').timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Starts the debounced backup timer (checks every 1 minute)
  void start() {
    if (_backgroundTimer != null) return;
    
    debugPrint('AutoBackupManager: Starting 1-minute background backup checker timer...');
    
    // Initialize Google Drive Excel backup system on startup asynchronously
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        await GoogleDriveExcelBackupService().initializeOnStartup();
        // Also perform initial check/sync on startup if there is anything pending
        await checkAndPerformBackup();
      } catch (e) {
        debugPrint('AutoBackupManager: Failed to initialize Google Drive Excel backup on startup: $e');
      }
    });

    _backgroundTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await checkAndPerformBackup();
    });
  }

  /// Stops the background timer
  void stop() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    debugPrint('AutoBackupManager: Stopped background backup checker timer.');
  }

  /// Triggers a pending backup status. Sets a persistent flag in SharedPreferences.
  Future<void> triggerBackupPending() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Update local database last modified timestamp
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await prefs.setString('local_db_last_modified_timestamp', nowStr);
    debugPrint('AutoBackupManager: local_db_last_modified_timestamp updated to: $nowStr');

    // Check if backups are blocked
    if (await BackupFreshnessService().areBackupsBlocked()) {
      debugPrint('AutoBackupManager: Backup mutation occurred, but backups/uploads are BLOCKED.');
      return;
    }

    await prefs.setBool('backup_pending', true);
    debugPrint('AutoBackupManager: Backup marked PENDING due to data mutation.');
    
    // Update sync status indicator state
    if (syncStatus.value != SyncStatus.syncing) {
      final hasNet = await isInternetAvailable();
      syncStatus.value = hasNet ? SyncStatus.syncing : SyncStatus.waitingForInternet;
    }
    
    // Cancel any existing debounce timers
    _syncDebounce?.cancel();
    
    // Debounce the actual backup upload (3 seconds) to merge rapid changes into one consolidated upload
    _syncDebounce = Timer(const Duration(seconds: 3), () async {
      try {
        await checkAndPerformBackup();
      } catch (e) {
        debugPrint('AutoBackupManager: Debounced sync execution failed: $e');
      }
    });
  }

  /// Checks if a backup is pending and if the user is connected, and performs it.
  Future<void> checkAndPerformBackup({bool forceManual = false, void Function(double progress)? onProgress}) async {
    // App Close Protection: background automatic uploads are disabled
    if (!BackupFreshnessService.isAppInForeground) {
      debugPrint('AutoBackupManager: App is in background. Aborting auto-backup.');
      return;
    }

    // Trigger timestamp validation check
    await BackupFreshnessService().checkFreshnessSilent();

    if (await BackupFreshnessService().areBackupsBlocked()) {
      debugPrint('AutoBackupManager: Backup blocked because Google Drive has a newer backup or freshness validation failed.');
      if (forceManual) {
        throw Exception('Backup operations are blocked because a newer backup exists on Google Drive or freshness validation failed.');
      }
      return;
    }

    if (DBHelper.isRestoring) {
      debugPrint('AutoBackupManager: Database is currently restoring. Skipping backup check...');
      if (forceManual) {
        throw Exception('Database restore is in progress. Cannot perform backup at this time.');
      }
      return;
    }

    if (_isBackingUp) {
      debugPrint('AutoBackupManager: Backup is already in progress, skipping check...');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final isPending = prefs.getBool('backup_pending') ?? false;
    
    if (!isPending && !forceManual) {
      // Sync complete, make sure status reflects synced if drive is connected and we are in waiting state
      final connected = await _driveService.isConnected();
      if (connected && (syncStatus.value == SyncStatus.waitingForInternet || syncStatus.value == SyncStatus.failed)) {
        syncStatus.value = SyncStatus.synced;
      }
      return;
    }

    // Check if user is signed in to Google Drive
    final connected = await _driveService.isConnected();
    if (!connected) {
      final email = prefs.getString('google_drive_account_email');
      if (email != null && email.isNotEmpty) {
        // User was logged in but silent sign in failed: access revoked or refresh token expired
        syncStatus.value = SyncStatus.reconnect;
      } else {
        syncStatus.value = SyncStatus.synced; // neutral state if user hasn't configured Drive backup yet
      }
      if (forceManual) {
        throw Exception('Google Drive account is not connected.');
      }
      return;
    }

    // Check internet connection
    final hasInternet = await isInternetAvailable();
    if (!hasInternet) {
      syncStatus.value = SyncStatus.waitingForInternet;
      debugPrint('AutoBackupManager: Offline. Waiting for internet...');
      if (forceManual) {
        throw Exception('No internet connection available.');
      }
      return;
    }

    _isBackingUp = true;
    syncStatus.value = SyncStatus.syncing;
    debugPrint('AutoBackupManager: Starting background backup process...');

    try {
      onProgress?.call(0.05);
      // 1. Run WAL checkpoint to ensure database file bytes are up-to-date
      final db = await DBHelper().database;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (e) {
        debugPrint('AutoBackupManager: WAL checkpoint failed: $e');
      }

      final dbPath = await getDatabasesPath();
      final Uint8List dbBytes;
      final dbFile = File(join(dbPath, 'loan_manager.db'));
      if (!await dbFile.exists()) {
        throw Exception('Database file does not exist.');
      }
      dbBytes = await dbFile.readAsBytes();

      final currentChecksum = BackupService.calculateSHA256(dbBytes);

      // 2. Perform Smart Upload Optimization: Check if database has changed
      final lastChecksum = prefs.getString('last_backed_up_db_checksum');
      if (currentChecksum == lastChecksum && !forceManual) {
        debugPrint('AutoBackupManager: Database is UNCHANGED (checksum matches). Skipping upload to save resources.');
        await prefs.setBool('backup_pending', false);
        syncStatus.value = SyncStatus.synced;
        _isBackingUp = false;
        return;
      }

      String? email = _driveService.currentUser?.email ?? prefs.getString('google_drive_account_email');

      // 3. Create encrypted backup package
      final encryptedBytes = await BackupService.createEncryptedBackup(email: email);

      // Read metadata for upload
      final borrowerCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM borrowers WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
      final loanCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM loans WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
      final paymentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM payments WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
      final expenseCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM expenses WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
      final investmentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM investments WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
      final serviceCostCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM service_costs WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;

      final metadata = {
        'app_version': '1.0.0',
        'schema_version': 12,
        'backup_timestamp': DateTime.now().toUtc().toIso8601String(),
        'borrower_count': borrowerCount,
        'loan_count': loanCount,
        'payment_count': paymentCount,
        'expense_count': expenseCount,
        'investment_count': investmentCount,
        'service_cost_count': serviceCostCount,
        'device_info': '${Platform.operatingSystem} - ${Platform.localHostname}',
        'android_version': Platform.operatingSystemVersion,
        'database_checksum': currentChecksum,
      };

      // 4. Upload ZIP backup to Google Drive
      await _driveService.uploadBackup(
        encryptedBytes,
        metadata,
        onProgress: (p) => onProgress?.call(0.1 + p * 0.5),
      );

      // 4b. Perform the persistent Excel backup on Google Drive
      debugPrint('AutoBackupManager: Triggering Google Drive Excel snapshot backup...');
      await GoogleDriveExcelBackupService().performBackup(
        force: true,
        onProgress: (p) => onProgress?.call(0.6 + p * 0.4),
      );

      // 5. Success cleanup
      await prefs.setString('last_backed_up_db_checksum', currentChecksum);
      await prefs.setBool('backup_pending', false);
      
      syncStatus.value = SyncStatus.synced;
      debugPrint('AutoBackupManager: Backup successfully completed and uploaded to Google Drive!');
      
      // Dispatch local notification confirming success
      await _notificationService.showSyncSuccess(isAutomatic: !forceManual);

      // Invoke UI update callback
      if (onBackupCompleted != null) {
        onBackupCompleted!();
      }
    } catch (e) {
      debugPrint('AutoBackupManager ERROR: Backup operation failed: $e');
      
      // Error classification: Auth issue vs. network issue
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') ||
          errStr.contains('unauthorized') ||
          errStr.contains('auth') ||
          errStr.contains('sign') ||
          errStr.contains('token') ||
          errStr.contains('invalid_grant')) {
        syncStatus.value = SyncStatus.reconnect;
      } else {
        final hasNet = await isInternetAvailable();
        if (!hasNet) {
          syncStatus.value = SyncStatus.waitingForInternet;
        } else {
          syncStatus.value = SyncStatus.failed;
        }
      }

      await _notificationService.showSyncFailure(e.toString());
      if (forceManual) {
        rethrow;
      }
    } finally {
      _isBackingUp = false;
    }
  }
}

