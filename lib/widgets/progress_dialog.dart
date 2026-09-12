import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/app_colors.dart';
import 'success_celebration_badge.dart';

class ProgressDialog extends StatefulWidget {
  final String title;
  final String successMessage;
  final String errorMessage;
  final Future<void> Function(void Function(double progress, String status) updateProgress) action;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.successMessage,
    required this.errorMessage,
    required this.action,
  });

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  double _progress = 0.0;
  String _status = '';
  bool _isCompleted = false;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _startAction();
  }

  void _startAction() async {
    try {
      await widget.action((progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress.clamp(0.0, 1.0);
            if (status.isNotEmpty) {
              _status = status;
            }
          });
        }
      });

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _isCompleted = true;
        });
        
        // Auto close after a short delay
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint('ProgressDialog action failed: $e');
      if (mounted) {
        setState(() {
          _isFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF34D399) : AppColors.primary;
    
    Widget content;
    List<Widget>? actions;

    if (_isCompleted) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SuccessCelebrationBadge(size: 96),
            const SizedBox(height: 16),
            Text(
              widget.successMessage.isNotEmpty ? widget.successMessage : 'Completed Successfully',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 17,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    } else if (_isFailed) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(LucideIcons.xCircle, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              widget.errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please try again.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
      actions = [
        Center(
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ];
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 18,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 22),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: _progress),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, animatedVal, _) {
                return Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return Container(
                              height: 10,
                              width: constraints.maxWidth * animatedVal.clamp(0.0, 1.0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    primaryColor,
                                    const Color(0xFF10B981),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _status.isNotEmpty ? _status : 'Please wait...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(animatedVal * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      content: content,
      actions: actions,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    );
  }
}
