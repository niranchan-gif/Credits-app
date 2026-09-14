import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update_info.dart';
import '../widgets/rocket_update_header.dart';
import '../config/update_message.dart';

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
  String _downloadSpeedText = '';
  String _etaText = '';
  bool _downloadSuccess = false;
  bool _isLaunching = false;
  bool _hasLaunched = false;
  bool _isCancelled = false;
  String _errorMessage = '';
  String? _downloadedApkPath;
  http.Client? _httpClient;

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  /// Downloads APK directly inside the app with live progress tracking
  Future<void> _startUpdate() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _errorMessage = 'Update URL is missing.');
      return;
    }

    // If APK was already downloaded and rocket launched, open installer directly
    if (_downloadedApkPath != null && await File(_downloadedApkPath!).exists() && _hasLaunched) {
      await _installApk(_downloadedApkPath!);
      return;
    }

    // Immediately start download and display progress bar without blocking dialogs!
    _isCancelled = false;
    setState(() {
      _isDownloading = true;
      _downloadSuccess = false;
      _isLaunching = false;
      _hasLaunched = false;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Connecting to server...';
      _downloadedSizeText = 'Preparing...';
      _downloadSpeedText = '';
      _etaText = '';
      _errorMessage = '';
    });

    try {
      final client = http.Client();
      _httpClient = client;

      final request = http.Request('GET', Uri.parse(widget.updateInfo.downloadUrl));
      request.headers['User-Agent'] = 'Credits-App-Updater';
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final fileName = 'credits_v${widget.updateInfo.version}_${DateTime.now().millisecondsSinceEpoch}.apk';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final sink = file.openWrite();

      DateTime lastUiUpdate = DateTime.now();
      DateTime lastSpeedTime = DateTime.now();
      int lastSpeedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();

        // Speed calculation every ~500ms
        final speedIntervalMs = now.difference(lastSpeedTime).inMilliseconds;
        if (speedIntervalMs >= 500) {
          final bytesSince = receivedBytes - lastSpeedBytes;
          final speedBytesSec = (bytesSince / (speedIntervalMs / 1000.0));

          if (speedBytesSec > 1024 * 1024) {
            _downloadSpeedText = '${(speedBytesSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
          } else if (speedBytesSec > 1024) {
            _downloadSpeedText = '${(speedBytesSec / 1024).toStringAsFixed(0)} KB/s';
          } else {
            _downloadSpeedText = '${speedBytesSec.toStringAsFixed(0)} B/s';
          }

          if (totalBytes > receivedBytes && speedBytesSec > 0) {
            final remainingSec = ((totalBytes - receivedBytes) / speedBytesSec).round();
            if (remainingSec <= 1) {
              _etaText = 'Almost done';
            } else if (remainingSec < 60) {
              _etaText = '~$remainingSec s left';
            } else {
              final mins = (remainingSec / 60).floor();
              final secs = remainingSec % 60;
              _etaText = '~$mins m ${secs}s left';
            }
          }
          lastSpeedTime = now;
          lastSpeedBytes = receivedBytes;
        }

        // Throttle UI setState to ~80ms for 60fps smooth animation
        if (now.difference(lastUiUpdate).inMilliseconds >= 80 || (totalBytes > 0 && receivedBytes >= totalBytes)) {
          lastUiUpdate = now;
          if (totalBytes > 0) {
            final progress = receivedBytes / totalBytes;
            final receivedMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _downloadProgress = progress.clamp(0.0, 1.0);
              _downloadedSizeText = '$receivedMB MB / $totalMB MB';
              _downloadStatusText = 'Downloading package...';
            });
          } else {
            final receivedMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _downloadedSizeText = '$receivedMB MB';
              _downloadStatusText = 'Downloading package...';
            });
          }
        }
      }

      await sink.flush();
      await sink.close();

      _downloadedApkPath = filePath;

      if (mounted) {
        final finalMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
        setState(() {
          // Keep progress card visible at 100% while the rocket ignites and launches!
          _downloadProgress = 1.0;
          _downloadSuccess = true;
          _isLaunching = true; // ROCKET BLASTS OFF WITH FIRE AND ASH!
          _downloadStatusText = 'Download Complete! Launching...';
          _downloadedSizeText = '$finalMB MB package verified';
          _downloadSpeedText = '';
          _etaText = '';
        });
      }
    } catch (e) {
      if (_isCancelled) {
        // User intentionally cancelled download - do NOT print stack trace or error to terminal
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadSuccess = false;
            _isLaunching = false;
            _downloadProgress = 0.0;
            _errorMessage = ''; // Do not display red error banner!
          });
        }
        return;
      }
      debugPrint('Update download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadSuccess = false;
          _isLaunching = false;
          _errorMessage = 'Download failed: ${e.toString().replaceAll('Exception:', '').trim()}';
        });
      }
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }

  /// Triggered when the rocket completes its flight into deep space
  Future<void> _onRocketLaunchComplete() async {
    if (!mounted) return;

    setState(() {
      _isDownloading = false;
      _hasLaunched = true;
    });

    // Automatically launch package installer to update the app!
    if (_downloadedApkPath != null) {
      await _installApk(_downloadedApkPath!);
    }
  }

  /// Triggers the Android package installer on the downloaded APK
  Future<void> _installApk(String filePath) async {
    try {
      debugPrint('ForceUpdateScreen: Opening installer for $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        setState(() => _errorMessage = 'Update package file not found. Please tap Update Now.');
        return;
      }

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('OpenFilex result: ${result.type} - ${result.message}');

      if (result.type != ResultType.done) {
        if (Platform.isAndroid) {
          final status = await Permission.requestInstallPackages.status;
          if (!status.isGranted) {
            final req = await Permission.requestInstallPackages.request();
            if (!req.isGranted) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Permission needed: Please enable "Install unknown apps" in Settings.';
                });
                await openAppSettings();
              }
            } else {
              await OpenFilex.open(
                filePath,
                type: 'application/vnd.android.package-archive',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error launching installer: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not open package installer: $e';
        });
      }
    }
  }

  void _cancelDownload() {
    _isCancelled = true;
    setState(() {
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadSuccess = false;
      _isLaunching = false;
      _downloadStatusText = '';
      _downloadedSizeText = '';
      _downloadSpeedText = '';
      _etaText = '';
      _errorMessage = '';
    });
    _httpClient?.close();
    _httpClient = null;

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(LucideIcons.info, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Download cancelled', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: const Color(0xFF1E3A31),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    // Detect active theme (Light vs Dark mode)
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Show progress card while downloading OR while rocket is in blastoff flight
    final bool showProgressBar = _isDownloading || (_isLaunching && !_hasLaunched);
    final bool isReady = _hasLaunched || (_downloadSuccess && _downloadedApkPath != null && !_isDownloading);

    // Feature checklist items from updateInfo or configured in UpdateMessageConfig
    final List<String> featureItems = widget.updateInfo.releaseNotes.isNotEmpty
        ? widget.updateInfo.releaseNotes
        : UpdateMessageConfig.releaseNotes;

    final String updateTitle = (widget.updateInfo.title != null && widget.updateInfo.title!.isNotEmpty)
        ? widget.updateInfo.title!
        : UpdateMessageConfig.title;

    final String updateSubtitle = (widget.updateInfo.message != null && widget.updateInfo.message!.isNotEmpty)
        ? widget.updateInfo.message!
        : UpdateMessageConfig.message;

    final Color bottomNavColor = isDark ? const Color(0xFF010E0A) : const Color(0xFFE4F0EB);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bottomNavColor,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: PopScope(
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
          backgroundColor: bottomNavColor,
          body: SizedBox.expand(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? const [
                          Color(0xFF031610),
                          Color(0xFF021711),
                          Color(0xFF010E0A),
                        ]
                      : const [
                          Color(0xFFF8FCFA),
                          Color(0xFFEFF7F3),
                          Color(0xFFE4F0EB),
                        ],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 1. Space Illustration Card with Animated Rocket (adapts to Light & Dark)
                                RocketUpdateHeader(
                                  isDownloading: _isDownloading,
                                  downloadProgress: _downloadProgress,
                                  isLaunching: _isLaunching,
                                  isDark: isDark,
                                  onLaunchComplete: _onRocketLaunchComplete,
                                ),
                                const SizedBox(height: 24),

                                // 2. Title & subtitle matching mockup typography
                                Text(
                                  updateTitle,
                                  style: GoogleFonts.leagueSpartan(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF142921),
                                    letterSpacing: -0.2,
                                    height: 1.25,
                                  ),
                                ),
                                if (updateSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    updateSubtitle,
                                    style: GoogleFonts.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF4A5F55),
                                    ),
                                  ),
                                ],
                                
                                const SizedBox(height: 18),

                                // 4. Feature Checklist matching reference mockup
                                ...featureItems.map((feature) => _buildCheckItem(feature, isDark)),

                                const SizedBox(height: 16),

                                // Error Message Display
                                if (_errorMessage.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF3B1212) : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                            : const Color(0xFFF87171).withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.alertCircle, color: Color(0xFFEF4444), size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _errorMessage,
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Flexible space so buttons sit naturally without dead white gap
                                const Spacer(),
                                const SizedBox(height: 16),

                                // 5. Interactive Progress Area while Downloading & Launching
                                if (showProgressBar) ...[
                                  _buildDownloadProgressCard(isDark),
                                  const SizedBox(height: 10),
                                  if (!_isLaunching)
                                    Center(
                                      child: TextButton.icon(
                                        onPressed: _cancelDownload,
                                        icon: const Icon(LucideIcons.x, size: 16),
                                        label: const Text('Cancel Download', style: TextStyle(fontWeight: FontWeight.w600)),
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                ],
                                if (!showProgressBar) ...[
                                  // Primary Action Button: "Update Now" or "Install Now"
                                  if (isReady) ...[
                                    _buildActionButton(
                                      text: 'Install Now',
                                      icon: LucideIcons.checkCircle2,
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                                      ),
                                      onPressed: () {
                                        if (_downloadedApkPath != null) {
                                          _installApk(_downloadedApkPath!);
                                        } else {
                                          _startUpdate();
                                        }
                                      },
                                    ),
                                  ] else ...[
                                    _buildActionButton(
                                      text: 'Update Now',
                                      icon: LucideIcons.rocket,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF13A383),
                                          Color(0xFF0A6853),
                                        ],
                                      ),
                                      onPressed: _startUpdate,
                                    ),
                                  ],

                                  const SizedBox(height: 10),

                                  // Secondary Button: "Update Later"
                                  Center(
                                    child: TextButton(
                                      onPressed: _skipUpdate,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      ),
                                      child: Text(
                                        'Update Later',
                                        style: GoogleFonts.manrope(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF4A5F55),
                                        ),
                                      ),
                                    ),
                                  ),

                                  Center(
                                    child: TextButton(
                                      onPressed: _openInBrowser,
                                      child: Text(
                                        'Download via Browser instead',
                                        style: GoogleFonts.manrope(
                                          fontSize: 12.5,
                                          color: isDark
                                              ? const Color(0xFFDAA464).withValues(alpha: 0.85)
                                              : const Color(0xFFAD752B),
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Checklist item matching the reference mockup styling
  Widget _buildCheckItem(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF07271E) : const Color(0xFFE1F2EB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF13A383).withValues(alpha: 0.35)
                    : const Color(0xFF13A383).withValues(alpha: 0.40),
                width: 1.2,
              ),
            ),
            child: Icon(
              LucideIcons.check,
              color: isDark ? const Color(0xFF13A383) : const Color(0xFF0B6D55),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF192A23),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bulletproof Download progress card using FractionallySizedBox (zero layout crashes)
  Widget _buildDownloadProgressCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07241B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF13A383).withValues(alpha: 0.4)
              : const Color(0xFF13A383).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF13A383).withValues(alpha: 0.08)
                : const Color(0xFF0A5844).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF13A383)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _downloadStatusText.isNotEmpty ? _downloadStatusText : 'Downloading...',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF142921),
                    ),
                  ),
                ],
              ),
              if (_downloadSpeedText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF13A383).withValues(alpha: 0.15)
                        : const Color(0xFFE2F3EB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF13A383).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.zap,
                        size: 11,
                        color: isDark ? const Color(0xFF13A383) : const Color(0xFF0B6D55),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _downloadSpeedText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isDark ? const Color(0xFF13A383) : const Color(0xFF0B6D55),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Rock-solid, crash-proof animated progress bar using FractionallySizedBox
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: _downloadProgress),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) {
              final double safeProgress = animatedValue.clamp(0.0, 1.0);

              return Column(
                children: [
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2ECE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: safeProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF13A383),
                              Color(0xFF10B981),
                              Color(0xFFFFDF73),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _downloadedSizeText,
                        style: GoogleFonts.manrope(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.7)
                              : const Color(0xFF52665C),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF13A383).withValues(alpha: 0.15)
                              : const Color(0xFFE2F3EB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(safeProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDark ? const Color(0xFF13A383) : const Color(0xFF0B6D55),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_etaText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _etaText,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFF6A7E75),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Wide pill button matching the reference mockup
  Widget _buildActionButton({
    required String text,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13A383).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
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

