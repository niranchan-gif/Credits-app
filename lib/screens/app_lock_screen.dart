import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _authService = AuthService();
  String _pin = '';
  bool _isError = false;
  bool _biometricEnabled = false;
  bool _hasPromptedBiometric = false;
  Timer? _lockoutTimer;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialAuth() async {
    _biometricEnabled = await _authService.isBiometricEnabled();
    if (mounted) {
      setState(() {});
    }
    
    // Only prompt biometric automatically once when the screen loads
    if (_biometricEnabled && !_authService.isLockedOut && !_hasPromptedBiometric) {
      _hasPromptedBiometric = true;
      _triggerBiometric();
    }
    _checkLockout();
  }

  Future<void> _triggerBiometric() async {
    final success = await _authService.authenticateWithBiometrics();
    // Use mounted check before calling callbacks that trigger navigation/state changes
    if (success && mounted) {
      widget.onUnlocked();
    }
  }

  void _checkLockout() {
    if (_authService.isLockedOut) {
      if (mounted) {
        setState(() => _lockoutSeconds = _authService.lockoutSecondsRemaining);
      }
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
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
          widget.onUnlocked();
        }
      } else {
        if (mounted) {
          setState(() {
            _pin = '';
            _isError = true;
          });
        }
        _checkLockout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Image.asset(
              'assets/icon/app_icon.png',
              width: 80,
              height: 80,
            ),
            const SizedBox(height: 16),
            const Text(
              'App Locked',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lockoutSeconds > 0
                  ? 'Try again in $_lockoutSeconds seconds'
                  : 'Enter PIN to unlock',
              style: TextStyle(
                color: _isError || _lockoutSeconds > 0 ? Colors.redAccent : Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 40),
            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _pin.length ? Colors.white : Colors.white24,
                  ),
                );
              }),
            ),
            const Spacer(),
            // Numpad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  _buildNumRow(['1', '2', '3']),
                  const SizedBox(height: 20),
                  _buildNumRow(['4', '5', '6']),
                  const SizedBox(height: 20),
                  _buildNumRow(['7', '8', '9']),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeyWidget(
                        _biometricEnabled
                            ? IconButton(
                                icon: const Icon(Icons.fingerprint, color: Colors.white, size: 32),
                                onPressed: _lockoutSeconds > 0 ? null : _triggerBiometric,
                              )
                            : const SizedBox(width: 70, height: 70),
                      ),
                      _buildKeyWidget(_buildNumButton('0')),
                      _buildKeyWidget(
                        IconButton(
                          icon: const Icon(Icons.backspace, color: Colors.white, size: 28),
                          onPressed: _lockoutSeconds > 0 ? null : () => _onKeyPress('delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildNumRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((n) => _buildKeyWidget(_buildNumButton(n))).toList(),
    );
  }

  Widget _buildKeyWidget(Widget child) {
    return SizedBox(width: 70, height: 70, child: Center(child: child));
  }

  Widget _buildNumButton(String num) {
    return TextButton(
      onPressed: _lockoutSeconds > 0 ? null : () => _onKeyPress(num),
      style: TextButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20),
        backgroundColor: Colors.white.withValues(alpha: 0.1),
      ),
      child: Text(
        num,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
