import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/app_update_info.dart';
import '../services/update_service.dart';

class ForceUpdateScreen extends StatefulWidget {
  final AppUpdateInfo updateInfo;
  final String currentVersion;
  final VoidCallback onSkip;

  const ForceUpdateScreen({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
    required this.onSkip,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _errorMessage = '';
  bool _downloadComplete = false;

  Future<void> _startUpdate() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _errorMessage = 'Update URL is missing. Please configure GitHub Releases.');
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = '';
      _downloadProgress = 0.0;
      _downloadComplete = false;
    });

    try {
      await _updateService.downloadAndInstallApk(
        widget.updateInfo.downloadUrl,
        (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
      );
      setState(() {
        _isDownloading = false;
        _downloadComplete = true;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Download failed. Please check your internet connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
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
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Premium Icon Presentation
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primary.withOpacity(0.2),
                            theme.colorScheme.primary.withOpacity(0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                            blurRadius: 40,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        LucideIcons.rocket,
                        size: 72,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Titles
                  Text(
                    'Time for an Upgrade',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.leagueSpartan(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A new version of Credits is ready. Update now to get the latest features and performance improvements.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Error Message
                  if (_errorMessage.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Release Notes (if any)
                  if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outline.withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.sparkles, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'What\'s New',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...widget.updateInfo.releaseNotes.take(3).map((note) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                                Expanded(
                                  child: Text(
                                    note,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  const Spacer(),

                  // Action Buttons
                  ElevatedButton(
                    onPressed: _isDownloading || _downloadComplete ? null : _startUpdate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      elevation: 8,
                      shadowColor: theme.colorScheme.primary.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _buildButtonChild(),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: (_isDownloading && !_downloadComplete) ? null : widget.onSkip,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      'Update later',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonChild() {
    if (_downloadComplete) {
      return const Text('Installing Update...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
    } else if (_isDownloading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text('Downloading ${(_downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );
    } else if (_errorMessage.isNotEmpty) {
      return const Text('RETRY UPDATE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
    } else {
      return const Text('UPDATE NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
    }
  }
}
