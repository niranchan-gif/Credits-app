import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update_info.dart';

class ForceUpdateScreen extends StatefulWidget {
  final AppUpdateInfo updateInfo;
  final int currentBuild;
  final Widget nextScreen;

  const ForceUpdateScreen({
    super.key,
    required this.updateInfo,
    required this.currentBuild,
    required this.nextScreen,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  String _downloadedSizeText = '';
  String _errorMessage = '';
  String? _downloadedApkPath;
  http.Client? _httpClient;

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  /// Ensures Android REQUEST_INSTALL_PACKAGES permission is granted
  Future<bool> _ensureInstallPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.requestInstallPackages.status;
      if (status.isGranted) {
        return true;
      }

      // Request permission (opens system setting toggle on Android 8.0+)
      final reqStatus = await Permission.requestInstallPackages.request();
      if (reqStatus.isGranted) {
        return true;
      }

      // If not granted, display guidance modal directing to Settings
      if (mounted) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(LucideIcons.shieldAlert, color: Color(0xFFDAA464), size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Permission Required',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: const Text(
              'To install this update directly, Android requires permission to "Install unknown apps" from Credits.\n\nPlease enable "Allow from this source" in Settings.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpen == true) {
          await openAppSettings();
          final recheck = await Permission.requestInstallPackages.status;
          return recheck.isGranted;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Permission check error: $e');
      return true;
    }
  }

  /// Downloads APK directly inside the app with live progress tracking
  Future<void> _startUpdate() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _errorMessage = 'Update URL is missing.');
      return;
    }

    // If APK was already downloaded, install directly
    if (_downloadedApkPath != null && await File(_downloadedApkPath!).exists()) {
      await _installApk(_downloadedApkPath!);
      return;
    }

    // Step 1: Pre-check permission
    final hasPermission = await _ensureInstallPermission();
    if (!hasPermission) {
      setState(() {
        _errorMessage = 'Permission required to install updates. Please allow "Install unknown apps".';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Connecting to server...';
      _downloadedSizeText = '';
      _errorMessage = '';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/credits-update-${widget.updateInfo.version}.apk';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(widget.updateInfo.downloadUrl));
      final streamedResponse = await _httpClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      setState(() {
        _downloadStatusText = 'Downloading update...';
      });

      await for (final chunk in streamedResponse.stream) {
        if (!_isDownloading) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          final receivedMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _downloadProgress = progress.clamp(0.0, 1.0);
            _downloadedSizeText = '$receivedMB MB / $totalMB MB';
          });
        } else {
          final receivedMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _downloadedSizeText = '$receivedMB MB';
          });
        }
      }

      await sink.flush();
      await sink.close();

      _downloadedApkPath = filePath;

      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadStatusText = 'Download complete!';
      });

      // Step 2: Trigger package installer
      await _installApk(filePath);

    } catch (e) {
      debugPrint('Update download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed';
        });
      }
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }

  /// Triggers the Android package installer on the downloaded APK
  Future<void> _installApk(String filePath) async {
    final hasPermission = await _ensureInstallPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Permission required to install. Tap "Install Now" after allowing in settings.';
        });
      }
      return;
    }

    try {
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        debugPrint('OpenFilex error: ${result.message}');
        if (mounted) {
          setState(() {
            _errorMessage = 'Could not open package installer';
          });
        }
      }
    } catch (e) {
      debugPrint('Error launching installer: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not open package installer';
        });
      }
    }
  }

  void _cancelDownload() {
    setState(() {
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadStatusText = '';
      _downloadedSizeText = '';
    });
    _httpClient?.close();
    _httpClient = null;
  }

  Future<void> _openInBrowser() async {
    final Uri url = Uri.parse(widget.updateInfo.downloadUrl);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _errorMessage = 'Could not open browser link.');
    }
  }

  void _skipUpdate() {
    if (_isDownloading) {
      _cancelDownload();
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget.nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isDownloading) {
          _cancelDownload();
          return;
        }
        _skipUpdate();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface,
                isDark ? const Color(0xFF021711) : theme.colorScheme.primary.withOpacity(0.05),
              ],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        // Icon
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary.withOpacity(0.12),
                            ),
                            child: Icon(
                              _downloadedApkPath != null
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.rocket,
                              size: 72,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        
                        // Title
                        Text(
                          _downloadedApkPath != null ? 'Update Ready' : 'Update Available',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.leagueSpartan(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'A new version of Credits is ready to install.\n\nCurrent Build: ${widget.currentBuild}   •   Latest Build: ${widget.updateInfo.version}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        
                        if (widget.updateInfo.releaseNotes.isNotEmpty && !_isDownloading) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.outline.withOpacity(0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "What's New:",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...widget.updateInfo.releaseNotes.map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '• ',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                            ),
                          ),
                        ],
                        
                        const Spacer(),

                        // Error Message
                        if (_errorMessage.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
                            ),
                            child: Text(
                              _errorMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Interactive Updating Area
                        if (_isDownloading) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.25),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _downloadStatusText.isNotEmpty ? _downloadStatusText : 'Downloading...',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    Text(
                                      '${(_downloadProgress * 100).toInt()}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: _downloadProgress > 0 ? _downloadProgress : null,
                                    minHeight: 10,
                                    backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                                  ),
                                ),
                                if (_downloadedSizeText.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      _downloadedSizeText,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton.icon(
                            onPressed: _cancelDownload,
                            icon: const Icon(LucideIcons.x, size: 18),
                            label: const Text('Cancel Download', style: TextStyle(fontWeight: FontWeight.w600)),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                          ),
                        ] else ...[
                          // Ready to Install button or Update Now button
                          if (_downloadedApkPath != null) ...[
                            ElevatedButton.icon(
                              onPressed: _startUpdate,
                              icon: const Icon(LucideIcons.checkCircle2, size: 20),
                              label: const Text('Install Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                elevation: 4,
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ] else ...[
                            ElevatedButton.icon(
                              onPressed: _startUpdate,
                              icon: const Icon(LucideIcons.downloadCloud, size: 20),
                              label: const Text('Update Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                elevation: 4,
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _skipUpdate,
                            icon: const Icon(LucideIcons.clock, size: 18),
                            label: const Text('Update Later', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              foregroundColor: theme.colorScheme.onSurfaceVariant,
                              side: BorderSide(
                                color: theme.colorScheme.outline.withOpacity(0.35),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: _openInBrowser,
                              child: Text(
                                'Download via Browser instead',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
