import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/auto_backup_manager.dart';
import '../services/google_drive_service.dart';
import '../utils/app_colors.dart';

class SyncStatusIndicator extends StatelessWidget {
  final bool compact;

  const SyncStatusIndicator({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: AutoBackupManager.syncStatus,
      builder: (context, status, _) {
        return GestureDetector(
          onTap: () => _handleTap(context, status),
          child: compact ? _buildCompact(context, status) : _buildFull(context, status),
        );
      },
    );
  }

  Widget _buildCompact(BuildContext context, SyncStatus status) {
    final IconData icon;
    final Color color;
    final String tooltip;

    switch (status) {
      case SyncStatus.synced:
        icon = LucideIcons.cloudLightning;
        color = AppColors.success;
        tooltip = 'Google Drive Synced';
        break;
      case SyncStatus.syncing:
        icon = LucideIcons.refreshCw;
        color = AppColors.accent;
        tooltip = 'Syncing...';
        break;
      case SyncStatus.waitingForInternet:
        icon = LucideIcons.wifiOff;
        color = AppColors.warning;
        tooltip = 'Offline - Sync Pending';
        break;
      case SyncStatus.failed:
        icon = LucideIcons.alertTriangle;
        color = AppColors.error;
        tooltip = 'Sync Failed - Tap to retry';
        break;
      case SyncStatus.reconnect:
        icon = LucideIcons.key;
        color = AppColors.error;
        tooltip = 'Authentication Required';
        break;
    }

    Widget iconWidget = Icon(icon, color: color, size: 20);

    if (status == SyncStatus.syncing) {
      iconWidget = _RotatingIcon(icon: icon, color: color, size: 20);
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity( 0.1),
          shape: BoxShape.circle,
        ),
        child: iconWidget,
      ),
    );
  }

  Widget _buildFull(BuildContext context, SyncStatus status) {
    final IconData icon;
    final Color color;
    final String label;

    switch (status) {
      case SyncStatus.synced:
        icon = LucideIcons.checkCircle;
        color = AppColors.success;
        label = 'Synced';
        break;
      case SyncStatus.syncing:
        icon = LucideIcons.refreshCw;
        color = AppColors.accent;
        label = 'Syncing...';
        break;
      case SyncStatus.waitingForInternet:
        icon = LucideIcons.wifiOff;
        color = AppColors.warning;
        label = 'Waiting for Internet';
        break;
      case SyncStatus.failed:
        icon = LucideIcons.alertTriangle;
        color = AppColors.error;
        label = 'Sync Failed';
        break;
      case SyncStatus.reconnect:
        icon = LucideIcons.key;
        color = AppColors.error;
        label = 'Reconnect Google Drive';
        break;
    }

    Widget iconWidget = Icon(icon, color: color, size: 14);

    if (status == SyncStatus.syncing) {
      iconWidget = _RotatingIcon(icon: icon, color: color, size: 14);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity( 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity( 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        _showSnackbar(context, '✅ Cloud backup is fully active and synchronized.', AppColors.success);
        break;
      case SyncStatus.syncing:
        _showSnackbar(context, '⏳ Syncing database changes in background...', AppColors.accent);
        break;
      case SyncStatus.waitingForInternet:
        _showOfflineOption(context);
        break;
      case SyncStatus.failed:
        _retrySync(context);
        break;
      case SyncStatus.reconnect:
        _showReconnectDialog(context);
        break;
    }
  }

  void _showSnackbar(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _retrySync(BuildContext context) async {
    _showSnackbar(context, '🔄 Retrying cloud synchronization...', AppColors.accent);
    try {
      await AutoBackupManager().checkAndPerformBackup(forceManual: true);
      if (context.mounted) {
        _showSnackbar(context, '✅ Sync retry completed successfully!', AppColors.success);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackbar(context, '❌ Sync failed: ${e.toString().replaceAll('Exception: ', '')}', AppColors.error);
      }
    }
  }

  Future<void> _showOfflineOption(BuildContext context) async {
    final hasNet = await AutoBackupManager.isInternetAvailable();
    if (!hasNet) {
      if (context.mounted) {
        _showSnackbar(context, '📶 Still offline. Auto-backup will run as soon as internet connection is detected.', AppColors.warning);
      }
    } else {
      if (context.mounted) {
        _retrySync(context);
      }
    }
  }

  void _showReconnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.key, color: AppColors.error),
            SizedBox(width: 12),
            Text('Reconnect Google Drive'),
          ],
        ),
        content: const Text(
          'Your Google Drive session has expired or permissions were revoked. '
          'Please reconnect your Google account to resume secure real-time cloud backups.\n\nLocal records are safe and intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showSnackbar(context, '🔗 Opening Google Authentication flow...', AppColors.accent);
              try {
                final account = await GoogleDriveService().connectAccount();
                if (account != null) {
                  if (context.mounted) {
                    _showSnackbar(context, '✅ Reconnected successfully as ${account.email}!', AppColors.success);
                  }
                  // Run sync on reconnection
                  await AutoBackupManager().checkAndPerformBackup();
                }
              } catch (e) {
                if (context.mounted) {
                  _showSnackbar(context, '❌ Reconnection failed: $e', AppColors.error);
                }
              }
            },
            child: const Text('Reconnect Now'),
          ),
        ],
      ),
    );
  }
}

class _RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _RotatingIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}

