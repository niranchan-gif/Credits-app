import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';


class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const String _keyPin = 'app_lock_pin';
  static const String _keyBiometricEnabled = 'app_lock_biometric_enabled';
  static const String _keyLockEnabled = 'app_lock_enabled';

  int _wrongAttempts = 0;
  DateTime? _lockoutUntil;

  // ─────────────────────────────────────────────────────────────────────────────
  // State Queries
  // ─────────────────────────────────────────────────────────────────────────────

  Future<bool> isLockEnabled() async {
    final val = await _storage.read(key: _keyLockEnabled);
    return val == 'true';
  }

  Future<bool> isBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  Future<bool> hasBiometricHardware() async {
    return await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Setup / Management
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> enableLock(String pin, bool useBiometric) async {
    await _storage.write(key: _keyPin, value: pin);
    await _storage.write(key: _keyBiometricEnabled, value: useBiometric ? 'true' : 'false');
    await _storage.write(key: _keyLockEnabled, value: 'true');
  }

  Future<void> disableLock() async {
    await _storage.delete(key: _keyLockEnabled);
    await _storage.delete(key: _keyPin);
    await _storage.delete(key: _keyBiometricEnabled);
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    final current = await _storage.read(key: _keyPin);
    if (current == oldPin) {
      await _storage.write(key: _keyPin, value: newPin);
      return true;
    }
    return false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled ? 'true' : 'false');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Authentication
  // ─────────────────────────────────────────────────────────────────────────────

  bool get isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      _wrongAttempts = 0;
      _lockoutUntil = null;
      return false;
    }
    return true;
  }

  int get lockoutSecondsRemaining {
    if (_lockoutUntil == null) return 0;
    final diff = _lockoutUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  Future<bool> authenticateWithBiometrics() async {
    if (isLockedOut) return false;
    try {
      final success = await _localAuth.authenticate(
        localizedReason: 'Unlock Credits app',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (success) {
        _wrongAttempts = 0;
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    if (isLockedOut) return false;

    final storedPin = await _storage.read(key: _keyPin);
    if (storedPin == pin) {
      _wrongAttempts = 0;
      return true;
    }

    _wrongAttempts++;
    if (_wrongAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return false;
  }
}

