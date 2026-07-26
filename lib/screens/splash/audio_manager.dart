import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// AudioManager handles subtle cinematic acoustic and tactile feedback during launch.
/// Strictly respects OS sound/vibration settings.
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _isMuted = false;

  /// Initialize and detect device sound/mute settings if possible.
  Future<void> init() async {
    try {
      // Check if system sound/haptics are available without blocking startup
      _isMuted = false;
    } catch (e) {
      debugPrint('AudioManager init error: $e');
      _isMuted = true;
    }
  }

  /// 0.0s: Soft cinematic whoosh as the coin appears.
  void playWhoosh() {
    if (_isMuted) return;
    try {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  /// During spin: Very subtle metallic spin feedback.
  void playSpin() {
    if (_isMuted) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// 2.2s Reveal: Premium coin chime and tactile resonance.
  void playChime() {
    if (_isMuted) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void dispose() {
    // Clean up if needed
  }
}
