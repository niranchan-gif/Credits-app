import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
  String _errorMessage = '';

  Future<void> _startUpdate() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _errorMessage = 'Update URL is missing.');
      return;
    }
    
    setState(() => _errorMessage = '');

    final Uri url = Uri.parse(widget.updateInfo.downloadUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        setState(() => _errorMessage = 'Could not open the update link.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error launching URL.');
    }
  }

  void _skipUpdate() {
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
    final isMandatory = widget.updateInfo.forceUpdate;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!isMandatory) {
          _skipUpdate();
        }
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
                          isMandatory ? 'Update Required' : 'Update Available',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.leagueSpartan(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'A new version of Credits is ${isMandatory ? 'required' : 'available'}.\n\nCurrent version: ${widget.currentBuild}\nLatest version: ${widget.updateInfo.version}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        
                        if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: widget.updateInfo.releaseNotes.map((note) => Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  '• $note',
                                  textAlign: TextAlign.left,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )).toList(),
                            ),
                          ),
                        ],
                        
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
                          onPressed: _startUpdate,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 4,
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: const Text('Update Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        if (!isMandatory) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _skipUpdate,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              foregroundColor: theme.colorScheme.onSurfaceVariant,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: const Text('Later', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
