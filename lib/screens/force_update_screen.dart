import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/app_update_info.dart';
import '../services/update_service.dart';

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
        _errorMessage = 'Download failed. Please check your internet connection.';
      });
    }
  }

  void _skipUpdate() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget.nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
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
                        // Simple Premium Icon
                        Center(
                          child: Icon(
                            LucideIcons.rocket,
                            size: 84,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Minimal Title
                        Text(
                          'Update Available',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.leagueSpartan(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'A new version of Credits is available.\n\nCurrent version: ${widget.currentBuild}\nNew version: ${widget.updateInfo.version}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        
                        const Spacer(),

                        // Error Message
                        if (_errorMessage.isNotEmpty) ...[
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Action Buttons
                        ElevatedButton(
                          onPressed: _isDownloading || _downloadComplete ? null : _startUpdate,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 4,
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: _buildButtonChild(),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: (_isDownloading && !_downloadComplete) ? null : _skipUpdate,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonChild() {
    if (_downloadComplete) {
      return const Text('Installing...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
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
      return const Text('Retry Update', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
    } else {
      return const Text('Update Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
    }
  }
}
