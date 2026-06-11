import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationService — singleton that manages local phone notifications
///
/// Shows native notification-center notifications for:
///   • Backup/sync success (auto or manual)
///   • Backup/sync failure
///
/// Usage:
///   await NotificationService().init();          ← call once in main()
///   NotificationService().showSyncSuccess();     ← after successful sync
///   NotificationService().showSyncFailure(msg);  ← after failed sync
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Notification channel config (Android) ─────────────────────────────────
  static const String _channelId = 'credits_backup';
  static const String _channelName = 'Backup & Sync';
  static const String _channelDesc =
      'Notifies when your data has been backed up to the cloud.';

  // ── Notification IDs ───────────────────────────────────────────────────────
  static const int _syncSuccessId = 1001;
  static const int _syncErrorId   = 1002;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization — call once in main() before runApp
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;



    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    // Request permissions for Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('NotificationService ▶ initialized');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public notification methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Show success notification after automatic or manual backup.
  /// [isAutomatic] — true for background auto-sync, false for manual sync.
  Future<void> showSyncSuccess({bool isAutomatic = false}) async {
    await _ensureInit();

    final title = isAutomatic ? '✅ Auto Backup Complete' : '✅ Backup Complete';
    const body = 'Your Credits data has been securely backed up to the cloud.';

    await _show(id: _syncSuccessId, title: title, body: body);
  }

  /// Show failure notification when backup/sync fails.
  Future<void> showSyncFailure(String reason) async {
    await _ensureInit();

    const title = '⚠️ Backup Failed';
    final body = 'Could not back up your data. ${reason.isNotEmpty ? reason : "Please try again."}';

    await _show(id: _syncErrorId, title: title, body: body);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {

    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details);
      debugPrint('NotificationService ▶ sent: $title');
    } catch (e) {
      debugPrint('NotificationService ▶ error sending notification: $e');
    }
  }
}

