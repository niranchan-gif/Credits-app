import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _authService = AuthService();
  bool _isLockEnabled = false;
  bool _isBiometricEnabled = false;
  bool _hasBiometricHardware = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _isLockEnabled = await _authService.isLockEnabled();
    _isBiometricEnabled = await _authService.isBiometricEnabled();
    _hasBiometricHardware = await _authService.hasBiometricHardware();
    setState(() => _isLoading = false);
  }

  Future<void> _toggleLock(bool val) async {
    if (val) {
      _showSetupDialog();
    } else {
      _showDisableDialog();
    }
  }

  Future<void> _toggleBiometric(bool val) async {
    await _authService.setBiometricEnabled(val);
    setState(() => _isBiometricEnabled = val);
  }

  void _showSetupDialog() {
    String pin = '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Setup PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter a 4-digit PIN to secure your app.'),
                const SizedBox(height: 16),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() => pin = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'PIN',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: pin.length == 4
                    ? () async {
                        Navigator.pop(ctx);
                        await _authService.enableLock(pin, _hasBiometricHardware);
                        _loadSettings();
                      }
                    : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDisableDialog() {
    String pin = '';
    bool error = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Disable App Lock'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter current PIN to disable app lock.'),
                const SizedBox(height: 16),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() {
                    pin = v;
                    error = false;
                  }),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'PIN',
                    errorText: error ? 'Incorrect PIN' : null,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: pin.length == 4
                    ? () async {
                        final success = await _authService.verifyPin(pin);
                        if (success) {
                          await _authService.disableLock();
                          if (mounted) Navigator.pop(ctx);
                          _loadSettings();
                        } else {
                          setDialogState(() => error = true);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Disable', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangePinDialog() {
    String oldPin = '';
    String newPin = '';
    bool error = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Change PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() {
                    oldPin = v;
                    error = false;
                  }),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Current PIN',
                    errorText: error ? 'Incorrect PIN' : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() => newPin = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'New PIN',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: oldPin.length == 4 && newPin.length == 4
                    ? () async {
                        final success = await _authService.changePin(oldPin, newPin);
                        if (success) {
                          if (mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('PIN changed successfully'), backgroundColor: Colors.green),
                          );
                        } else {
                          setDialogState(() => error = true);
                        }
                      }
                    : null,
                child: const Text('Change'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Security Settings', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable App Lock', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Require PIN or biometrics to open app'),
            value: _isLockEnabled,
            onChanged: _toggleLock,
          ),
          if (_isLockEnabled) ...[
            const Divider(),
            if (_hasBiometricHardware)
              SwitchListTile(
                title: const Text('Biometric Unlock', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Use fingerprint or face to unlock'),
                value: _isBiometricEnabled,
                onChanged: _toggleBiometric,
              ),
            ListTile(
              title: const Text('Change PIN', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showChangePinDialog,
            ),
          ],
        ],
      ),
    );
  }
}
