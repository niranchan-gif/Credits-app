import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/voice_typing_service.dart';
import '../../utils/app_colors.dart';
import 'app_keyboard_controller.dart';
import 'app_keyboard_types.dart';

/// The visual keyboard component matching the Quick Add aesthetic with
/// maximized key sizes, instantaneous touch responsiveness, and synced haptics.
class AppKeyboardView extends StatelessWidget {
  const AppKeyboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = AppKeyboardController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isVisible) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2024) : const Color(0xFFE8EBF0),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.12) 
                    : Colors.black.withValues(alpha: 0.09),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Top Utility Toolbar
                _buildToolbar(context, isDark, controller),

                // 2. Main Keyboard Area according to mode
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: controller.isVoiceTyping
                        ? _VoiceTypingStudioWidget(
                            key: const ValueKey('voice_typing_studio'),
                            isDark: isDark,
                            controller: controller,
                          )
                        : switch (controller.currentMode) {
                            AppKeyboardMode.qwerty => _buildQwertyLayout(isDark, controller),
                            AppKeyboardMode.symbols => _buildSymbolsLayout(isDark, controller),
                            AppKeyboardMode.numeric => _buildNumpadLayout(isDark, controller),
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Top toolbar with mode tabs, field label, quick clear, and dismiss button.
  Widget _buildToolbar(BuildContext context, bool isDark, AppKeyboardController controller) {
    final text = controller.currentController?.text ?? '';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18191D) : const Color(0xFFDEE2E8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Mode switch tabs (ABC / 123 / #+=)
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF26282E) : const Color(0xFFCFD5DF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeTab(
                  label: 'ABC',
                  isActive: controller.currentMode == AppKeyboardMode.qwerty,
                  onTap: () => controller.setMode(AppKeyboardMode.qwerty),
                  isDark: isDark,
                ),
                _buildModeTab(
                  label: '123',
                  isActive: controller.currentMode == AppKeyboardMode.numeric,
                  onTap: () => controller.setMode(AppKeyboardMode.numeric),
                  isDark: isDark,
                ),
                _buildModeTab(
                  label: '#+=',
                  isActive: controller.currentMode == AppKeyboardMode.symbols,
                  onTap: () => controller.setMode(AppKeyboardMode.symbols),
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Field Label
          Expanded(
            child: Text(
              controller.label ?? 'Keyboard',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),

          // Voice Typing button
          _buildVoiceToolbarButton(context, isDark, controller),

          // Clear button if field has text
          if (text.isNotEmpty)
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.clearAll();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF383C46) : const Color(0xFFD6DBE4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ),

          // Dismiss chevron
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              controller.hide();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.chevronDown,
                size: 20,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            color: isActive
                ? Colors.white
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // QWERTY LAYOUT (Maximized key sizes)
  // ==========================================
  Widget _buildQwertyLayout(bool isDark, AppKeyboardController controller) {
    const row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
    const row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
    const row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

    final isShifted = controller.isShifted;
    final isCapsLock = controller.isCapsLock;

    return Column(
      key: const ValueKey('qwerty_layout'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Number Row (1–9, 0)
        Row(
          children: [
            '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
          ].map((char) {
            return _buildNumberRowKey(
              text: char,
              onTap: () => controller.insertText(char),
              isDark: isDark,
            );
          }).toList(),
        ),

        // Row 1 (10 keys)
        Row(
          children: row1.map((char) {
            final displayChar = isShifted ? char.toUpperCase() : char;
            return _buildKey(
              text: displayChar,
              onTap: () => controller.insertText(displayChar),
              isDark: isDark,
            );
          }).toList(),
        ),

        // Row 2 (9 keys, padded horizontally for classic staggering)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: row2.map((char) {
              final displayChar = isShifted ? char.toUpperCase() : char;
              return _buildKey(
                text: displayChar,
                onTap: () => controller.insertText(displayChar),
                isDark: isDark,
              );
            }).toList(),
          ),
        ),

        // Row 3: Shift (flex 13) + 7 letters (flex 10 each) + Backspace (flex 13)
        Row(
          children: [
            // Shift Key
            _buildSpecialKey(
              flex: 13,
              isDark: isDark,
              onTap: controller.toggleShift,
              child: Icon(
                isCapsLock ? Icons.arrow_circle_up_rounded : Icons.arrow_upward_rounded,
                size: 22,
                color: isShifted
                    ? AppColors.accent
                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
              ),
              customBg: isShifted
                  ? (isDark ? const Color(0xFF3E434D) : const Color(0xFFCBD2DF))
                  : null,
            ),

            // Letters z - m
            ...row3.map((char) {
              final displayChar = isShifted ? char.toUpperCase() : char;
              return _buildKey(
                flex: 10,
                text: displayChar,
                onTap: () => controller.insertText(displayChar),
                isDark: isDark,
              );
            }),

            // Backspace Key with hold-to-repeat deletion!
            _buildSpecialKey(
              flex: 13,
              isDark: isDark,
              isRepeatable: true,
              onTap: controller.backspace,
              onLongPress: controller.clearAll,
              child: Icon(
                Icons.backspace_rounded,
                size: 20,
                color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
              ),
            ),
          ],
        ),

        // Row 4: ?123, Voice key, Space, Comma, Period, Action
        Row(
          children: [
            // Switch to symbols
            _buildSpecialKey(
              flex: 13,
              isDark: isDark,
              text: '?123',
              onTap: () => controller.setMode(AppKeyboardMode.symbols),
            ),

            // Voice typing mic key
            _buildVoiceKey(flex: 11, isDark: isDark, controller: controller),

            // Spacebar (Expanded & comfortable)
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
                child: _InstantKeySurface(
                  isDark: isDark,
                  height: 54,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    controller.insertText(' ');
                  },
                  child: Text(
                    'space',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),

            // Comma
            _buildKey(
              flex: 9,
              text: ',',
              onTap: () => controller.insertText(','),
              isDark: isDark,
            ),

            // Period
            _buildKey(
              flex: 9,
              text: '.',
              onTap: () => controller.insertText('.'),
              isDark: isDark,
            ),

            // Action button (Done/Next/Search)
            _buildActionButton(flex: 16, isDark: isDark, controller: controller),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // SYMBOLS LAYOUT (Clean, balanced 10-key grid!)
  // ==========================================
  Widget _buildSymbolsLayout(bool isDark, AppKeyboardController controller) {
    const row1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    const row2 = ['@', '#', '₹', '%', '&', '-', '+', '(', ')', '/'];
    const row3 = ['*', '"', '\'', ':', ';', '!', '?', '_'];

    return Column(
      key: const ValueKey('symbols_layout'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Numbers (10 keys)
        Row(
          children: row1.map((char) {
            return _buildKey(
              text: char,
              onTap: () => controller.insertText(char),
              isDark: isDark,
            );
          }).toList(),
        ),

        // Row 2: Common symbols (10 keys)
        Row(
          children: row2.map((char) {
            return _buildKey(
              text: char,
              onTap: () => controller.insertText(char),
              isDark: isDark,
            );
          }).toList(),
        ),

        // Row 3: Balanced 10-key row (Left special + 8 symbols + Right Backspace)
        Row(
          children: [
            // Left toggle/extra symbol
            _buildSpecialKey(
              flex: 11,
              isDark: isDark,
              text: '=\\<',
              onTap: () {
                HapticFeedback.selectionClick();
                controller.insertText('=');
              },
            ),

            // 8 standard symbols (each flex 10)
            ...row3.map((char) {
              return _buildKey(
                flex: 10,
                text: char,
                onTap: () => controller.insertText(char),
                isDark: isDark,
              );
            }),

            // Backspace Key (Balanced flex: 11, identical to left key!)
            _buildSpecialKey(
              flex: 11,
              isDark: isDark,
              isRepeatable: true,
              onTap: controller.backspace,
              onLongPress: controller.clearAll,
              child: Icon(
                Icons.backspace_rounded,
                size: 20,
                color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
              ),
            ),
          ],
        ),

        // Row 4: ABC, Voice key, Space, Comma, Period, Action
        Row(
          children: [
            // Switch back to ABC
            _buildSpecialKey(
              flex: 13,
              isDark: isDark,
              text: 'ABC',
              onTap: () => controller.setMode(AppKeyboardMode.qwerty),
            ),

            // Voice typing mic key
            _buildVoiceKey(flex: 11, isDark: isDark, controller: controller),

            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
                child: _InstantKeySurface(
                  isDark: isDark,
                  height: 54,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    controller.insertText(' ');
                  },
                  child: Text(
                    'space',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),

            _buildKey(
              flex: 9,
              text: ',',
              onTap: () => controller.insertText(','),
              isDark: isDark,
            ),

            _buildKey(
              flex: 9,
              text: '.',
              onTap: () => controller.insertText('.'),
              isDark: isDark,
            ),

            _buildActionButton(flex: 16, isDark: isDark, controller: controller),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // NUMPAD LAYOUT (Maximized 62dp Large Keys)
  // ==========================================
  Widget _buildNumpadLayout(bool isDark, AppKeyboardController controller) {
    return Column(
      key: const ValueKey('numpad_layout'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1, 2, 3
        Row(
          children: [
            _buildLargeNumKey(text: '1', onTap: () => controller.insertText('1'), isDark: isDark),
            _buildLargeNumKey(text: '2', onTap: () => controller.insertText('2'), isDark: isDark),
            _buildLargeNumKey(text: '3', onTap: () => controller.insertText('3'), isDark: isDark),
          ],
        ),

        // Row 2: 4, 5, 6
        Row(
          children: [
            _buildLargeNumKey(text: '4', onTap: () => controller.insertText('4'), isDark: isDark),
            _buildLargeNumKey(text: '5', onTap: () => controller.insertText('5'), isDark: isDark),
            _buildLargeNumKey(text: '6', onTap: () => controller.insertText('6'), isDark: isDark),
          ],
        ),

        // Row 3: 7, 8, 9
        Row(
          children: [
            _buildLargeNumKey(text: '7', onTap: () => controller.insertText('7'), isDark: isDark),
            _buildLargeNumKey(text: '8', onTap: () => controller.insertText('8'), isDark: isDark),
            _buildLargeNumKey(text: '9', onTap: () => controller.insertText('9'), isDark: isDark),
          ],
        ),

        // Row 4: Backspace, 0, Action
        Row(
          children: [
            // Backspace with repeat hold-to-delete
            _buildLargeSpecialKey(
              isDark: isDark,
              isRepeatable: true,
              onTap: controller.backspace,
              onLongPress: controller.clearAll,
              child: Icon(
                Icons.backspace_rounded,
                size: 24,
                color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
              ),
            ),

            // 0
            _buildLargeNumKey(text: '0', onTap: () => controller.insertText('0'), isDark: isDark),

            // Action (Done / Next)
            _buildLargeActionKey(isDark: isDark, controller: controller),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // KEY ATOMS & REUSABLE BUILDERS
  // ==========================================
  Widget _buildKey({
    required String text,
    required VoidCallback onTap,
    required bool isDark,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 54,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberRowKey({
    required String text,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 38,
          customBg: isDark ? const Color(0xFF2A2D35) : const Color(0xFFD0D5DF),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1E293B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey({
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    String? text,
    Widget? child,
    Color? customBg,
    bool isRepeatable = false,
    int flex = 10,
  }) {
    final bgColor = customBg ?? (isDark ? const Color(0xFF32363F) : const Color(0xFFD6DBE4));

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 54,
          customBg: bgColor,
          isRepeatable: isRepeatable,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: child ?? Text(
                text ?? '',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required int flex,
    required bool isDark,
    required AppKeyboardController controller,
  }) {
    final (label, icon) = switch (controller.action) {
      AppKeyboardAction.next => ('Next', LucideIcons.arrowRight),
      AppKeyboardAction.search => ('Search', LucideIcons.search),
      AppKeyboardAction.send => ('Send', LucideIcons.send),
      AppKeyboardAction.newLine => ('Enter', LucideIcons.cornerDownLeft),
      AppKeyboardAction.done => ('Done', LucideIcons.checkCircle),
    };

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 54,
          customBg: AppColors.accent,
          customBorder: Border.all(color: AppColors.accent, width: 1.2),
          onTap: () {
            HapticFeedback.heavyImpact();
            controller.performAction();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(icon, size: 14, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Large Numpad Keys ---
  Widget _buildLargeNumKey({
    required String text,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 3.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 62,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeSpecialKey({
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool isRepeatable = false,
    required Widget child,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 3.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 62,
          isRepeatable: isRepeatable,
          customBg: isDark ? const Color(0xFF353942) : const Color(0xFFDFE3EA),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          onLongPress: onLongPress,
          child: child,
        ),
      ),
    );
  }

  Widget _buildLargeActionKey({
    required bool isDark,
    required AppKeyboardController controller,
  }) {
    final (label, icon) = switch (controller.action) {
      AppKeyboardAction.next => ('Next', LucideIcons.arrowRight),
      AppKeyboardAction.search => ('Search', LucideIcons.search),
      _ => ('Done', LucideIcons.checkCircle),
    };

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 3.5),
        child: _InstantKeySurface(
          isDark: isDark,
          height: 62,
          customBg: AppColors.accent,
          customBorder: Border.all(color: AppColors.accent, width: 1.2),
          onTap: () {
            HapticFeedback.heavyImpact();
            controller.performAction();
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(icon, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Voice Typing Components ---
  Widget _buildVoiceToolbarButton(
    BuildContext context,
    bool isDark,
    AppKeyboardController controller,
  ) {
    final voiceService = VoiceTypingService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([voiceService, controller]),
      builder: (context, _) {
        final isListening = voiceService.isListening || controller.isVoiceTyping;
        final isTamil = voiceService.isTamil;

        return GestureDetector(
          onTap: () => _handleVoiceToggle(context, controller),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isListening
                  ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                  : (isDark ? const Color(0xFF26282E) : const Color(0xFFD0D6E2)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isListening
                    ? const Color(0xFFEF4444)
                    : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                width: 1.1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.mic,
                  size: 14,
                  color: isListening ? const Color(0xFFEF4444) : AppColors.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  isTamil ? 'தமிழ்' : 'EN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isListening
                        ? const Color(0xFFEF4444)
                        : (isDark ? Colors.white : const Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceKey({
    required int flex,
    required bool isDark,
    required AppKeyboardController controller,
  }) {
    final voiceService = VoiceTypingService.instance;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.2, vertical: 2.5),
        child: AnimatedBuilder(
          animation: Listenable.merge([voiceService, controller]),
          builder: (context, _) {
            final isListening = voiceService.isListening || controller.isVoiceTyping;
            final isTamil = voiceService.isTamil;

            return _InstantKeySurface(
              isDark: isDark,
              height: 54,
              customBg: isListening
                  ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                  : (isDark ? const Color(0xFF32363F) : const Color(0xFFD6DBE4)),
              onTap: () {
                _handleVoiceToggle(context, controller);
              },
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.mic,
                      size: 18,
                      color: isListening
                          ? const Color(0xFFEF4444)
                          : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      isTamil ? 'தமிழ்' : 'EN',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: isListening
                            ? const Color(0xFFEF4444)
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleVoiceToggle(BuildContext context, AppKeyboardController controller) async {
    HapticFeedback.mediumImpact();
    final voiceService = VoiceTypingService.instance;
    if (controller.isVoiceTyping || voiceService.isListening) {
      await voiceService.stopListening();
      controller.stopVoiceTyping();
    } else {
      controller.startVoiceTyping();
    }
  }
}

/// Dedicated voice dictation panel with real-time Tamil transcription,
/// interactive pulse mic, visualizer equalizer, and quick language switcher.
class _VoiceTypingStudioWidget extends StatefulWidget {
  final bool isDark;
  final AppKeyboardController controller;

  const _VoiceTypingStudioWidget({
    super.key,
    required this.isDark,
    required this.controller,
  });

  @override
  State<_VoiceTypingStudioWidget> createState() => _VoiceTypingStudioWidgetState();
}

class _VoiceTypingStudioWidgetState extends State<_VoiceTypingStudioWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final VoiceTypingService _voiceService = VoiceTypingService.instance;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceInput();
    });
  }

  Future<void> _startVoiceInput() async {
    if (_voiceService.isListening) return;

    final success = await _voiceService.initialize();
    if (!success) {
      if (mounted) setState(() {});
      return;
    }

    await _voiceService.startListening(
      onResult: (words) {
        widget.controller.updateVoiceTranscription(words);
      },
      onDone: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _stopVoiceInput() async {
    await _voiceService.stopListening();
    widget.controller.stopVoiceTyping();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_voiceService, widget.controller, _pulseController]),
      builder: (context, _) {
        final isListening = _voiceService.isListening;
        final isTamil = _voiceService.isTamil;
        final currentText = widget.controller.currentController?.text ?? '';
        final error = _voiceService.errorMessage;

        return Container(
          height: 254,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF181A1F) : const Color(0xFFDEE3EB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // 1. Status Bar & Language Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Status beacon
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isListening ? const Color(0xFFEF4444) : Colors.grey,
                            boxShadow: isListening
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isListening
                                ? (isTamil ? 'பேசுங்கள்...' : 'Listening...')
                                : (isTamil ? 'மைக் தட்டி பேசவும்' : 'Tap mic to speak'),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isListening
                                  ? (widget.isDark ? Colors.white : const Color(0xFF0F172A))
                                  : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Language Toggle Chip (தமிழ் <-> English)
                  GestureDetector(
                    onTap: () async {
                      await _voiceService.toggleLanguage();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF262931) : const Color(0xFFCED5E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _voiceService.languageDisplayName,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.swap_horiz_rounded,
                            size: 15,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. Transcribed live text box or error notice
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF131518) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isListening
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : (widget.isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.07)),
                      width: 1,
                    ),
                  ),
                  child: error != null
                      ? Center(
                          child: Text(
                            error,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : SingleChildScrollView(
                          reverse: true,
                          child: Text(
                            currentText.isNotEmpty
                                ? currentText
                                : (isTamil
                                    ? 'தமிழில் பேசவும்... (எ.கா: சரவணன், வட்டி 500, தவணை)'
                                    : 'Speak in English... (e.g. John, Interest 500)'),
                            style: TextStyle(
                              fontSize: currentText.isNotEmpty ? 15.5 : 12.5,
                              fontWeight: currentText.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
                              color: currentText.isNotEmpty
                                  ? (widget.isDark ? Colors.white : const Color(0xFF0F172A))
                                  : (widget.isDark ? Colors.grey[500] : Colors.grey[500]),
                              height: 1.35,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // 3. Audio Equalizer Waveform & Glowing Mic Button
              SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Left 3 audio equalizer bars
                    _buildWaveBar(0, isListening),
                    const SizedBox(width: 4),
                    _buildWaveBar(1, isListening),
                    const SizedBox(width: 4),
                    _buildWaveBar(2, isListening),
                    const SizedBox(width: 14),

                    // Central Glowing Microphone Orb
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        if (isListening) {
                          await _voiceService.stopListening();
                        } else {
                          await _startVoiceInput();
                        }
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isListening)
                            Transform.scale(
                              scale: 0.95 + (_pulseController.value * 0.22),
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: isListening
                                    ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
                                    : [AppColors.accent, AppColors.accent.withValues(alpha: 0.85)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isListening ? const Color(0xFFEF4444) : AppColors.accent)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              isListening ? LucideIcons.mic : LucideIcons.micOff,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 14),
                    // Right 3 audio equalizer bars
                    _buildWaveBar(3, isListening),
                    const SizedBox(width: 4),
                    _buildWaveBar(4, isListening),
                    const SizedBox(width: 4),
                    _buildWaveBar(5, isListening),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 4. Bottom Controls: Keyboard button, Clear, Done
              Row(
                children: [
                  // Back to Keyboard
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _stopVoiceInput();
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.isDark ? const Color(0xFF262931) : const Color(0xFFCED5E0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.keyboard,
                                size: 16,
                                color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isTamil ? 'விசைப்பலகை' : 'Keyboard',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isDark ? Colors.grey[300] : Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Clear button (if has text)
                  if (currentText.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        widget.controller.clearAll();
                      },
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isTamil ? 'அழி' : 'Clear',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],

                  // Done / Accept button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _stopVoiceInput();
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.check,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isTamil ? 'முடிந்தது' : 'Done',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaveBar(int index, bool isListening) {
    final multipliers = [0.6, 1.2, 0.8, 1.0, 1.3, 0.7];
    final sound = _voiceService.soundLevel;
    final dynamicHeight = isListening
        ? math.max(6.0, math.min(32.0, (sound + 2.0) * 3.0 * multipliers[index] * (_pulseController.value * 0.5 + 0.75)))
        : 6.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: 4,
      height: dynamicHeight,
      decoration: BoxDecoration(
        color: isListening ? AppColors.accent : Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Instantaneous key surface that triggers onTap on onTapDown for 0ms latency
/// with synchronous haptics and auto-repeat hold support.
class _InstantKeySurface extends StatefulWidget {
  final bool isDark;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isRepeatable;
  final Widget child;
  final Color? customBg;
  final Border? customBorder;

  const _InstantKeySurface({
    required this.isDark,
    required this.height,
    required this.onTap,
    this.onLongPress,
    this.isRepeatable = false,
    required this.child,
    this.customBg,
    this.customBorder,
  });

  @override
  State<_InstantKeySurface> createState() => _InstantKeySurfaceState();
}

class _InstantKeySurfaceState extends State<_InstantKeySurface> {
  bool _isPressed = false;
  Timer? _initialDelayTimer;
  Timer? _repeatTimer;

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);

    // Instant execution on finger contact!
    widget.onTap();

    if (widget.isRepeatable) {
      _initialDelayTimer = Timer(const Duration(milliseconds: 350), () {
        _repeatTimer = Timer.periodic(const Duration(milliseconds: 65), (_) {
          widget.onTap();
        });
      });
    }
  }

  void _onTapUp(TapUpDetails details) {
    _cleanup();
  }

  void _onTapCancel() {
    _cleanup();
  }

  void _cleanup() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
    _initialDelayTimer?.cancel();
    _repeatTimer?.cancel();
    _initialDelayTimer = null;
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultBg = widget.isDark ? const Color(0xFF2E3138) : Colors.white;
    final baseBg = widget.customBg ?? defaultBg;
    final pressedBg = widget.isDark
        ? Color.lerp(baseBg, Colors.white, 0.12)!
        : Color.lerp(baseBg, Colors.black, 0.08)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        height: widget.height,
        decoration: BoxDecoration(
          color: _isPressed ? pressedBg : baseBg,
          borderRadius: BorderRadius.circular(12),
          border: widget.customBorder ?? Border.all(
            color: widget.isDark 
                ? Colors.white.withValues(alpha: _isPressed ? 0.3 : 0.15) 
                : Colors.black.withValues(alpha: _isPressed ? 0.2 : 0.11),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.4 : 0.08),
              blurRadius: _isPressed ? 1 : 3,
              offset: Offset(0, _isPressed ? 0.5 : 1.5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
