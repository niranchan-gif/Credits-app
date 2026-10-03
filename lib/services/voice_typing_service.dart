import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Singleton service managing speech-to-text with primary support for Tamil (ta_IN) and English.
class VoiceTypingService extends ChangeNotifier {
  static final VoiceTypingService instance = VoiceTypingService._();
  VoiceTypingService._();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _hasPermission = false;
  double _soundLevel = 0.0;
  String _currentLocaleId = 'ta_IN'; // Default to Tamil (India)
  String _lastRecognizedWords = '';
  String? _errorMessage;

  List<stt.LocaleName> _availableLocales = [];

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get hasPermission => _hasPermission;
  double get soundLevel => _soundLevel;
  String get currentLocaleId => _currentLocaleId;
  String get lastRecognizedWords => _lastRecognizedWords;
  String? get errorMessage => _errorMessage;
  List<stt.LocaleName> get availableLocales => _availableLocales;
  bool get isTamil => _currentLocaleId.startsWith('ta');

  /// Initialize speech engine and check permissions
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final status = await Permission.microphone.request();
      _hasPermission = status.isGranted;
      if (!_hasPermission) {
        _errorMessage = 'Microphone permission denied';
        notifyListeners();
        return false;
      }

      final available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );

      _isInitialized = available;
      if (available) {
        _availableLocales = await _speech.locales();
        _selectBestTamilLocale();
      } else {
        _errorMessage = 'Speech recognition not available on this device';
      }

      notifyListeners();
      return available;
    } catch (e) {
      _errorMessage = 'Failed to initialize speech: $e';
      notifyListeners();
      return false;
    }
  }

  String get languageLabel => isTamil ? 'தமிழ்' : 'EN';
  String get languageDisplayName => isTamil ? 'தமிழ் (Tamil)' : 'English (India)';

  void Function(String words)? _currentOnResult;
  void Function()? _currentOnDone;

  /// Finds and selects the best Tamil locale supported by device
  void _selectBestTamilLocale() {
    if (_availableLocales.isEmpty) {
      _currentLocaleId = 'ta_IN';
      return;
    }
    final tamilLocale = _availableLocales.firstWhere(
      (l) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        return id == 'ta_in' || id.startsWith('ta');
      },
      orElse: () => stt.LocaleName('ta_IN', 'Tamil (India)'),
    );
    _currentLocaleId = tamilLocale.localeId;
  }

  /// Finds and selects the best English locale supported by device
  void _selectBestEnglishLocale() {
    if (_availableLocales.isEmpty) {
      _currentLocaleId = 'en_IN';
      return;
    }
    final enLocale = _availableLocales.firstWhere(
      (l) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        return id == 'en_in' || id == 'en_us' || id.startsWith('en');
      },
      orElse: () => stt.LocaleName('en_IN', 'English (India)'),
    );
    _currentLocaleId = enLocale.localeId;
  }

  /// Switch between Tamil and English. If listening, seamlessly restarts with the new language.
  Future<void> toggleLanguage() async {
    HapticFeedback.selectionClick();
    final wasListening = _isListening;
    final cachedResultCb = _currentOnResult;
    final cachedDoneCb = _currentOnDone;

    if (wasListening) {
      await stopListening();
    }

    if (isTamil) {
      _selectBestEnglishLocale();
    } else {
      _selectBestTamilLocale();
    }
    notifyListeners();

    if (wasListening && cachedResultCb != null) {
      await Future.delayed(const Duration(milliseconds: 150));
      await startListening(
        onResult: cachedResultCb,
        onDone: cachedDoneCb,
      );
    }
  }

  /// Set specific language locale
  void setLocale(String localeId) {
    _currentLocaleId = localeId;
    notifyListeners();
  }

  /// Start recording and transcribing speech
  Future<void> startListening({
    required void Function(String words) onResult,
    void Function()? onDone,
  }) async {
    _currentOnResult = onResult;
    _currentOnDone = onDone;

    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return;
    }

    _errorMessage = null;
    _lastRecognizedWords = '';
    _soundLevel = 0.0;
    HapticFeedback.mediumImpact();

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          _lastRecognizedWords = result.recognizedWords;
          onResult(result.recognizedWords);
          notifyListeners();
          if (result.finalResult) {
            onDone?.call();
          }
        },
        onSoundLevelChange: (level) {
          _soundLevel = level;
          notifyListeners();
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _currentLocaleId,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      _isListening = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Speech error: $e';
      _isListening = false;
      notifyListeners();
    }
  }

  /// Stop listening and finalize
  Future<void> stopListening() async {
    if (!_isListening) return;
    HapticFeedback.lightImpact();
    await _speech.stop();
    _isListening = false;
    _soundLevel = 0.0;
    notifyListeners();
  }

  /// Cancel listening
  Future<void> cancelListening() async {
    HapticFeedback.lightImpact();
    await _speech.cancel();
    _isListening = false;
    _soundLevel = 0.0;
    _currentOnResult = null;
    _currentOnDone = null;
    notifyListeners();
  }

  void _onStatus(String status) {
    if (status == 'listening') {
      _isListening = true;
    } else if (status == 'notListening' || status == 'done') {
      _isListening = false;
      _soundLevel = 0.0;
    }
    notifyListeners();
  }

  void _onError(SpeechRecognitionError error) {
    _errorMessage = error.errorMsg;
    _isListening = false;
    _soundLevel = 0.0;
    notifyListeners();
  }
}
