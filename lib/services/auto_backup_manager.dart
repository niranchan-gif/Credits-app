import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_service.dart';
import 'notification_service.dart';
import '../database/db_helper.dart';
import 'backup_freshness_service.dart';
import 'google_drive_json_backup_service.dart';
import 'json_backup_service.dart';

enum SyncStatus { synced, syncing, waitingForInternet, failed, reconnect }

class AutoBackupManager {
  static final AutoBackupManager _instance = AutoBackupManager._internal();
  factory AutoBackupManager() => _instance;
  AutoBackupManager._internal();

  final GoogleDriveService _driveService = GoogleDriveService();
  final NotificationService _notificationService = NotificationService();
  
  Timer? _backgroundTimer;
  static final ValueNotifier<SyncStatus> syncStatus = ValueNotifier<SyncStatus>(SyncStatus.synced);
  VoidCallback? onBackupCompleted;

  static Future<bool> isInternetAvailable() async {
    try {
      final result = await InternetAddress.lookup('clients3.google.com').timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) { return false; }
  }

  void start() {
    if (_backgroundTimer != null && _backgroundTimer!.isActive) return;
    Future.delayed(const Duration(seconds: 2), () async => await _checkPendingUploads());
    _backgroundTimer = Timer.periodic(const Duration(minutes: 1), (timer) async => await _checkPendingUploads());
  }

  void stop() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> _checkPendingUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final isPending = prefs.getBool('json_upload_pending') ?? false;
    if (!isPending) return;
    
    if (_driveService.currentUser == null) {
      syncStatus.value = SyncStatus.reconnect;
      return;
    }

    if (!await isInternetAvailable()) {
      syncStatus.value = SyncStatus.waitingForInternet;
      return;
    }

    syncStatus.value = SyncStatus.syncing;
    try {
      final cdbLocalPath = join((await getApplicationDocumentsDirectory()).path, 'credits_backup.json.enc');
      await GoogleDriveJsonBackupService().uploadJson(cdbLocalPath);
      syncStatus.value = SyncStatus.synced;
      onBackupCompleted?.call();
    } catch (e) {
      syncStatus.value = SyncStatus.failed;
    }
  }

  Future<void> checkAndPerformBackup({bool forceManual = false, void Function(double progress)? onProgress}) async {
    if (forceManual) {
      syncStatus.value = SyncStatus.syncing;
      onProgress?.call(0.1);
      JsonBackupService().triggerBackup();
      await Future.delayed(const Duration(seconds: 2));
      syncStatus.value = SyncStatus.synced;
      onBackupCompleted?.call();
    }
  }
}
