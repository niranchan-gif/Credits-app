import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../../services/voice_typing_service.dart';
import 'app_keyboard_types.dart';

/// Central singleton controller for the custom in-app keyboard.
class AppKeyboardController extends ChangeNotifier {
  static final AppKeyboardController instance = AppKeyboardController._();
  AppKeyboardController._();

  bool _isVisible = false;
  TextEditingController? _currentController;
  FocusNode? _currentFocusNode;
  AppKeyboardType _keyboardType = AppKeyboardType.text;
  AppKeyboardMode _currentMode = AppKeyboardMode.qwerty;
  AppKeyboardAction _action = AppKeyboardAction.done;
  VoidCallback? _onAction;
  void Function(String)? _onChanged;
  String? _label;

  bool _isShifted = false;
  bool _isCapsLock = false;
  DateTime? _lastShiftTap;

  // Voice typing integration
  String _voiceInitialText = '';
  bool _isVoiceTyping = false;

  // Getters
  bool get isVisible => _isVisible;
  TextEditingController? get currentController => _currentController;
  FocusNode? get currentFocusNode => _currentFocusNode;
  AppKeyboardType get keyboardType => _keyboardType;
  AppKeyboardMode get currentMode => _currentMode;
  AppKeyboardAction get action => _action;
  bool get isVoiceTyping => _isVoiceTyping;
  String get voiceInitialText => _voiceInitialText;
  bool get isShifted => _isShifted || _isCapsLock;
  bool get isCapsLock => _isCapsLock;
  String? get label => _label;

  void _onFocusChanged() {
    if (_currentFocusNode != null && !_currentFocusNode!.hasFocus) {
      hide();
    }
  }

  void _safeNotifyListeners() {
    try {
      final binding = WidgetsBinding.instance;
      final phase = binding.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        binding.addPostFrameCallback((_) {
          notifyListeners();
        });
      } else {
        notifyListeners();
      }
    } catch (_) {
      notifyListeners();
    }
  }

  void _safeNotifyListenersDeferred() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (_) {
      notifyListeners();
    }
  }

  /// Attach a text editing controller and focus node to the custom keyboard.
  void attach({
    required TextEditingController controller,
    required FocusNode focusNode,
    AppKeyboardType type = AppKeyboardType.text,
    AppKeyboardAction action = AppKeyboardAction.done,
    VoidCallback? onAction,
    void Function(String)? onChanged,
    String? label,
  }) {
    // If previously attached to another node, remove listener from it
    if (_currentFocusNode != null && _currentFocusNode != focusNode) {
      try {
        _currentFocusNode!.removeListener(_onFocusChanged);
      } catch (_) {}
    }

    _currentController = controller;
    _currentFocusNode = focusNode;
    _keyboardType = type;
    _action = action;
    _onAction = onAction;
    _onChanged = onChanged;
    _label = label;

    // Listen to focus changes to auto-hide when focus is lost (widget closes, tab switches, etc.)
    try {
      focusNode.removeListener(_onFocusChanged);
      focusNode.addListener(_onFocusChanged);
    } catch (_) {}

    // Automatically default to numeric numpad for numbers/phones, QWERTY for text
    if (type == AppKeyboardType.number || type == AppKeyboardType.phone) {
      _currentMode = AppKeyboardMode.numeric;
    } else {
      _currentMode = AppKeyboardMode.qwerty;
    }

    _isShifted = false;
    _isCapsLock = false;
    _isVisible = true;
    _safeNotifyListeners();
  }

  /// Detach when a focus node loses focus or widget is disposed.
  void detach(FocusNode? node) {
    if (node == null || _currentFocusNode == node) {
      hide();
    }
  }

  /// Explicitly hide the keyboard.
  void hide() {
    if (!_isVisible && _currentFocusNode == null && _currentController == null) {
      return;
    }
    if (_isVoiceTyping) {
      VoiceTypingService.instance.stopListening();
      _isVoiceTyping = false;
    }
    _isVisible = false;

    final node = _currentFocusNode;
    _currentFocusNode = null;
    _currentController = null;
    _onAction = null;
    _onChanged = null;
    _label = null;

    if (node != null) {
      try {
        node.removeListener(_onFocusChanged);
      } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (node.hasFocus) {
            node.unfocus();
          }
        } catch (_) {}
      });
    }

    _safeNotifyListenersDeferred();
  }

  /// Start voice typing mode
  void startVoiceTyping() {
    _voiceInitialText = _currentController?.text ?? '';
    _isVoiceTyping = true;
    notifyListeners();
  }

  /// Stop voice typing and keep whatever transcribed
  void stopVoiceTyping() {
    _isVoiceTyping = false;
    notifyListeners();
  }

  /// Cancel voice typing and revert to pre-speech text
  void cancelVoiceTyping() {
    if (_currentController != null) {
      _currentController!.value = TextEditingValue(
        text: _voiceInitialText,
        selection: TextSelection.collapsed(offset: _voiceInitialText.length),
      );
      _onChanged?.call(_voiceInitialText);
    }
    _isVoiceTyping = false;
    notifyListeners();
  }

  /// Update input field with real-time transcribed speech
  void updateVoiceTranscription(String spokenWords) {
    if (_currentController == null) return;

    final initial = _voiceInitialText.trim();
    final combined = initial.isEmpty
        ? spokenWords
        : '$initial $spokenWords';

    _currentController!.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
    _onChanged?.call(combined);
    notifyListeners();
  }

  /// Explicitly show the keyboard.
  void show() {
    if (!_isVisible && _currentController != null) {
      _isVisible = true;
      notifyListeners();
    }
  }

  /// Switch keyboard layout mode (QWERTY, Symbols, or Numpad).
  void setMode(AppKeyboardMode mode) {
    HapticFeedback.lightImpact();
    _currentMode = mode;
    notifyListeners();
  }

  /// Toggle Shift / CapsLock state.
  void toggleShift() {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    if (_lastShiftTap != null && now.difference(_lastShiftTap!) < const Duration(milliseconds: 350)) {
      // Double tap -> CapsLock
      _isCapsLock = !_isCapsLock;
      _isShifted = _isCapsLock;
      _lastShiftTap = null;
    } else {
      if (_isCapsLock) {
        _isCapsLock = false;
        _isShifted = false;
      } else {
        _isShifted = !_isShifted;
      }
      _lastShiftTap = now;
    }
    notifyListeners();
  }

  /// Insert a single character or string at current cursor/selection position.
  void insertText(String text) {
    if (_currentController == null) return;

    final controller = _currentController!;
    final currentText = controller.text;
    final selection = controller.selection;

    final start = selection.isValid && selection.start >= 0 ? selection.start : currentText.length;
    final end = selection.isValid && selection.end >= 0 ? selection.end : currentText.length;

    // Apply casing if single letter and shifted
    String charToInsert = text;
    if (charToInsert.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(charToInsert)) {
      charToInsert = isShifted ? charToInsert.toUpperCase() : charToInsert.toLowerCase();
    }

    final newText = currentText.replaceRange(start, end, charToInsert);
    final newOffset = start + charToInsert.length;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    // Auto-reset shift if not in caps lock
    if (_isShifted && !_isCapsLock) {
      _isShifted = false;
    }

    _onChanged?.call(newText);
    notifyListeners();
  }

  /// Backspace: deletes selection or character before cursor.
  void backspace() {
    if (_currentController == null) return;

    final controller = _currentController!;
    final currentText = controller.text;
    final selection = controller.selection;

    final start = selection.isValid && selection.start >= 0 ? selection.start : currentText.length;
    final end = selection.isValid && selection.end >= 0 ? selection.end : currentText.length;

    if (start != end) {
      final newText = currentText.replaceRange(start, end, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
      _onChanged?.call(newText);
      notifyListeners();
    } else if (start > 0) {
      final newText = currentText.replaceRange(start - 1, start, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start - 1),
      );
      _onChanged?.call(newText);
      notifyListeners();
    }
  }

  /// Clear entire field text.
  void clearAll() {
    if (_currentController == null) return;
    _currentController!.clear();
    _onChanged?.call('');
    notifyListeners();
  }

  /// Perform the bottom-right action (Done, Next, Search, etc.).
  void performAction() {
    HapticFeedback.heavyImpact();
    if (_onAction != null) {
      _onAction!();
      return;
    }

    if (_action == AppKeyboardAction.next) {
      _currentFocusNode?.nextFocus();
    } else if (_action == AppKeyboardAction.newLine) {
      insertText('\n');
    } else {
      // Done or Search
      hide();
    }
  }
}

/// Navigator observer that automatically hides the in-app keyboard whenever
/// any route (dialog, bottom sheet, full screen) is popped, pushed, or removed.
class AppKeyboardNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    AppKeyboardController.instance.hide();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      AppKeyboardController.instance.hide();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    AppKeyboardController.instance.hide();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    AppKeyboardController.instance.hide();
  }
}

