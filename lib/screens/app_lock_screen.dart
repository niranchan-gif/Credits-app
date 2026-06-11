
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'dart:async';


class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  String _pin = '';
  bool _isError = false;
  bool _biometricEnabled = false;
  bool _hasPromptedBiometric = false;
  Timer? _lockoutTimer;
  int _lockoutSeconds = 0;

  // Animations
  late AnimationController _shakeController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _checkInitialAuth();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialAuth() async {
    _biometricEnabled = await _authService.isBiometricEnabled();
    if (mounted) setState(() {});
    if (_biometricEnabled && !_authService.isLockedOut && !_hasPromptedBiometric) {
      _hasPromptedBiometric = true;
      await Future.delayed(const Duration(milliseconds: 600));
      _triggerBiometric();
    }
    _checkLockout();
  }

  Future<void> _triggerBiometric() async {
    final success = await _authService.authenticateWithBiometrics();
    if (success && mounted) {
      HapticFeedback.lightImpact();
      widget.onUnlocked();
    }
  }

  void _checkLockout() {
    if (_authService.isLockedOut) {
      if (mounted) setState(() => _lockoutSeconds = _authService.lockoutSecondsRemaining);
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() {
          _lockoutSeconds = _authService.lockoutSecondsRemaining;
          if (_lockoutSeconds <= 0) {
            timer.cancel();
            _isError = false;
          }
        });
      });
    }
  }

  void _onKeyPress(String key) async {
    if (_authService.isLockedOut) return;
    HapticFeedback.selectionClick();

    setState(() {
      _isError = false;
      if (key == 'delete') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += key;
      }
    });

    if (_pin.length == 4) {
      final success = await _authService.verifyPin(_pin);
      if (success) {
        if (mounted) {
          HapticFeedback.lightImpact();
          widget.onUnlocked();
        }
      } else {
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() { _pin = ''; _isError = true; });
          _shakeController.forward(from: 0);
        }
        _checkLockout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A2332), const Color(0xFF0D1B2A), const Color(0xFF162031)]
                : [const Color(0xFF1E4235), const Color(0xFF285A48), const Color(0xFF1A3A2E)],
          ),
        ),
        child: Stack(
          children: [
            // Background decorative circles
            _buildBackgroundDecor(),
            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _buildLockIcon(),
                    const SizedBox(height: 24),
                    _buildTitle(),
                    const SizedBox(height: 8),
                    _buildSubtitle(),
                    const SizedBox(height: 48),
                    _buildPinDots(),
                    const Spacer(flex: 3),
                    _buildNumpad(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundDecor() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _CircleDecorPainter()),
      ),
    );
  }

  Widget _buildLockIcon() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, __) => Transform.scale(
        scale: _pulseAnimation.value,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity( 0.12),
            border: Border.all(color: Colors.white.withOpacity( 0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity( 0.05),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      'App Locked',
      style: TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSubtitle() {
    final text = _lockoutSeconds > 0
        ? 'Too many attempts. Try again in $_lockoutSeconds s'
        : _isError
            ? 'Incorrect PIN. Try again'
            : _biometricEnabled
                ? 'Use fingerprint or enter PIN'
                : 'Enter your PIN to continue';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        text,
        key: ValueKey(text),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _isError || _lockoutSeconds > 0
              ? const Color(0xFFFF8A80)
              : Colors.white.withOpacity( 0.65),
          fontSize: 14,
          fontWeight: _isError ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (_, child) {
        final offset = math.sin(_shakeAnimation.value * math.pi * 6) * 10.0;
        return Transform.translate(
          offset: Offset(_isError ? offset : 0, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: filled ? 18 : 14,
            height: filled ? 18 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (_isError ? const Color(0xFFFF8A80) : Colors.white)
                  : Colors.white.withOpacity( 0.25),
              boxShadow: filled
                  ? [BoxShadow(color: Colors.white.withOpacity( 0.3), blurRadius: 8, spreadRadius: 1)]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          _numRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _numRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _numRow(['7', '8', '9']),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _biometricEnabled
                  ? _buildActionButton(
                      onTap: _lockoutSeconds > 0 ? null : _triggerBiometric,
                      child: Icon(
                        Icons.fingerprint_rounded,
                        color: _lockoutSeconds > 0
                            ? Colors.white.withOpacity( 0.3)
                            : Colors.white,
                        size: 34,
                      ),
                    )
                  : const SizedBox(width: 72, height: 72),
              _buildNumButton('0'),
              _buildActionButton(
                onTap: _lockoutSeconds > 0 ? null : () => _onKeyPress('delete'),
                child: Icon(
                  Icons.backspace_rounded,
                  color: _pin.isEmpty || _lockoutSeconds > 0
                      ? Colors.white.withOpacity( 0.3)
                      : Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numRow(List<String> nums) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: nums.map(_buildNumButton).toList(),
    );
  }

  Widget _buildNumButton(String num) {
    final disabled = _lockoutSeconds > 0;
    return _buildKeyBase(
      onTap: disabled ? null : () => _onKeyPress(num),
      child: Text(
        num,
        style: TextStyle(
          color: disabled ? Colors.white.withOpacity( 0.3) : Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionButton({VoidCallback? onTap, required Widget child}) {
    return _buildKeyBase(onTap: onTap, child: child, isAction: true);
  }

  Widget _buildKeyBase({VoidCallback? onTap, required Widget child, bool isAction = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isAction
              ? Colors.white.withOpacity( 0.06)
              : Colors.white.withOpacity( 0.10),
          border: Border.all(
            color: Colors.white.withOpacity( isAction ? 0.08 : 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity( 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Draws subtle decorative circles in the background
class _CircleDecorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;

    paint.color = Colors.white.withOpacity( 0.04);
    paint.strokeWidth = 1;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.1), 120, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 160, paint);

    paint.color = Colors.white.withOpacity( 0.03);
    paint.strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), 220, paint);

    paint.color = Colors.white.withOpacity( 0.06);
    paint.strokeWidth = 0.8;
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.2), 80, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

