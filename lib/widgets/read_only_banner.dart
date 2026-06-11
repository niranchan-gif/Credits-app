import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/backup_freshness_service.dart';

class ReadOnlyBanner extends StatefulWidget {
  const ReadOnlyBanner({super.key});

  @override
  State<ReadOnlyBanner> createState() => _ReadOnlyBannerState();
}

class _ReadOnlyBannerState extends State<ReadOnlyBanner> {
  bool _isLoading = false;

  Future<void> _handleRetry() async {
    setState(() => _isLoading = true);
    try {
      await BackupFreshnessService().checkFreshness();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFFFF9F43) : const Color(0xFFD67300);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3E2C1C) : const Color(0xFFFFF4E5),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFFB5702A) : const Color(0xFFFFD19A),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              LucideIcons.wifiOff,
              color: accentColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Internet Required",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: accentColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accentColor,
                    ),
                  )
                : TextButton(
                    onPressed: _handleRetry,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: accentColor,
                    ),
                    child: const Text(
                      "Retry",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
