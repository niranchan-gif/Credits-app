import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

import '../services/auth_service.dart';
import '../services/google_drive_service.dart';
import '../services/backup_freshness_service.dart';
import '../services/auto_backup_manager.dart';
import '../providers/theme_provider.dart';
import '../providers/loan_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/premium_card.dart';
import '../widgets/progress_dialog.dart';
import '../database/db_helper.dart';
import '../models/borrower.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'backup_restore_screen.dart';
import 'auth/sign_in_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  bool _isLockEnabled = false;
  bool _isBiometricEnabled = false;
  bool _hasBiometricHardware = false;
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _developerModeEnabled = false;
  int _tapCount = 0;
  DateTime? _lastTapTime;

  void _handleSettingsTap() {
    final now = DateTime.now();

    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(seconds: 5)) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    debugPrint('Developer tap count: $_tapCount');

    if (_tapCount >= 7) {
      if (!_developerModeEnabled) {
        setState(() => _developerModeEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Developer Mode Enabled'), backgroundColor: AppColors.success),
        );
      }
      _tapCount = 0;
    }
  }

  Future<void> _generateTestBorrowers() async {
    setState(() => _isGenerating = true);
    final db = DBHelper();
    final random = Random();
    const uuid = Uuid();
    
    try {
      debugPrint('Developer Tool: Generating 500 test borrowers...');
      
      int baseCode = int.tryParse(await db.generateBorrowerCode()) ?? 1;
      
      for (int i = 0; i < 500; i++) {
        final phone = '9${random.nextInt(900000000) + 100000000}';
        
        final borrower = Borrower(
          borrowerCode: (baseCode + i).toString(),
          name: 'Test Borrower ${uuid.v4().substring(0, 5)}',
          phone: phone,
          address: 'Test Address $i',
        );
        
        final bId = await db.insertBorrower(borrower);
        
        // Random loans
        final numLoans = random.nextInt(3) + 1; // 1 to 3 loans
        for (int j = 0; j < numLoans; j++) {
          final loanAmt = (random.nextInt(50) + 10) * 1000.0;
          final intAmt = loanAmt * 0.1;
          
          final loanDate = DateTime.now().subtract(Duration(days: random.nextInt(100)));
          
          final loan = Loan(
            borrowerId: bId,
            loanAmount: loanAmt,
            interestAmount: intAmt,
            loanDate: loanDate,
            status: 'active',
          );
          
          final lId = await db.insertLoan(loan);
          
          // Random payments
          if (random.nextBool()) {
            final payAmt = (random.nextInt(10) + 1) * 500.0;
            final payment = Payment(
              loanId: lId,
              amount: payAmt,
              paymentDate: loanDate.add(Duration(days: random.nextInt(30))),
            );
            await db.insertPayment(payment);
          }
        }
      }
      
      debugPrint('Developer Tool: Successfully generated 500 borrowers with loans/payments');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generated 500 Test Borrowers'), backgroundColor: AppColors.success),
        );
      }
      
      if (mounted) {
        context.read<LoanProvider>().loadBorrowers();
      }
      
    } catch (e) {
      debugPrint('Developer Tool Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating data: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _confirmClearLocalDatabase(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Local Database'),
        content: const Text(
          'This will permanently delete all local borrowers, loans, payments, expenses, and investments from this device. '
          'Please make sure you have exported a backup first.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => ProgressDialog(
                  title: 'Clearing Local Database',
                  successMessage: '✓ Clear Completed',
                  errorMessage: 'Clear Failed',
                  action: (updateProgress) async {
                    updateProgress(0.3, 'Wiping borrowers data...');
                    await DBHelper().clearAllUserData();
                    
                    updateProgress(0.8, 'Reloading local provider...');
                    if (mounted) {
                      await context.read<LoanProvider>().loadBorrowers();
                    }
                    updateProgress(1.0, 'Clear completed!');
                  },
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Clear Local Data'),
          ),
        ],
      ),
    );
  }

  void _confirmFactoryReset(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Factory Reset App'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This will delete your database and all local settings/preferences from this device. This action cannot be undone.'),
              const SizedBox(height: 16),
              const Text('Type RESET to confirm:'),
              TextField(
                controller: ctrl,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(hintText: 'RESET'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: ctrl.text == 'RESET'
                  ? () async {
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => ProgressDialog(
                          title: 'Factory Resetting App',
                          successMessage: '✓ Reset Completed',
                          errorMessage: 'Reset Failed',
                          action: (updateProgress) async {
                            updateProgress(0.2, 'Wiping local tables...');
                            await DBHelper().clearAllUserData();
                            
                            updateProgress(0.6, 'Clearing shared preferences...');
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            
                            updateProgress(0.8, 'Reloading local provider...');
                            if (mounted) {
                              await context.read<LoanProvider>().loadBorrowers();
                            }
                            updateProgress(1.0, 'Reset completed!');
                          },
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Factory Reset'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _isLockEnabled = await _authService.isLockEnabled();
    _isBiometricEnabled = await _authService.isBiometricEnabled();
    _hasBiometricHardware = await _authService.hasBiometricHardware();
    if (mounted) {
      setState(() => _isLoading = false);
    }
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
    String confirmPin = '';
    bool confirmStep = false;
    bool mismatch = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final current = confirmStep ? confirmPin : pin;
          final title = confirmStep ? 'Confirm PIN' : 'Set PIN';
          final subtitle = mismatch
              ? 'PINs do not match. Try again.'
              : confirmStep
                  ? 'Re-enter your 4-digit PIN'
                  : 'Choose a 4-digit PIN to lock your app';

          void onKey(String key) {
            setDialogState(() {
              mismatch = false;
              if (key == 'del') {
                if (confirmStep) {
                  if (confirmPin.isNotEmpty) confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                } else {
                  if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
                }
              } else {
                if (confirmStep) { if (confirmPin.length < 4) confirmPin += key; }
                else { if (pin.length < 4) pin += key; }
              }
            });
            if (!confirmStep && pin.length == 4) {
              Future.delayed(const Duration(milliseconds: 150), () {
                if (ctx.mounted) setDialogState(() => confirmStep = true);
              });
            } else if (confirmStep && confirmPin.length == 4) {
              Future.delayed(const Duration(milliseconds: 150), () async {
                if (pin == confirmPin) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _authService.enableLock(pin, _hasBiometricHardware);
                  _loadSettings();
                  
                } else {
                  if (ctx.mounted) setDialogState(() { mismatch = true; confirmPin = ''; });
                }
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              const Icon(Icons.lock_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 8),
              Text(title),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subtitle, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13,
                      color: mismatch ? AppColors.error : Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < current.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? (mismatch ? AppColors.error : AppColors.accent)
                            : Theme.of(context).colorScheme.onSurface.withOpacity( 0.12),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                ...[['1','2','3'],['4','5','6'],['7','8','9']].map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: row.map((n) => _miniNumBtn(n, onKey, context)).toList()),
                )),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  const SizedBox(width: 52, height: 52),
                  _miniNumBtn('0', onKey, context),
                  SizedBox(width: 52, height: 52,
                    child: IconButton(onPressed: () => onKey('del'),
                        icon: const Icon(Icons.backspace_rounded, size: 22))),
                ]),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
          );
        },
      ),
    );
  }

  Widget _miniNumBtn(String n, void Function(String) onKey, BuildContext ctx) {
    return InkWell(
      onTap: () => onKey(n),
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(ctx).colorScheme.onSurface.withOpacity( 0.06),
        ),
        child: Center(child: Text(n, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
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
                const SizedBox(height: 20),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() {
                    pin = v;
                    error = false;
                  }),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 16, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    errorText: error ? 'Incorrect PIN' : null,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: pin.length == 4
                    ? () async {
                        final navigator = Navigator.of(ctx);
                        final success = await _authService.verifyPin(pin);
                        if (success) {
                          await _authService.disableLock();
                          if (mounted) { navigator.pop(); }
                          _loadSettings();
                          
                        } else {
                          setDialogState(() => error = true);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Disable', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Signing out will disconnect your Google Account. Your data will remain on this device and you can access it by signing back in with the same account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => ProgressDialog(
                  title: 'Signing Out',
                  successMessage: '✓ Signed Out',
                  errorMessage: 'Error Signing Out',
                  action: (updateProgress) async {
                    updateProgress(0.5, 'Disconnecting Google Account...');
                    await GoogleDriveService().disconnectAccount();
                    
                    updateProgress(0.8, 'Closing local database...');
                    await DBHelper().switchDatabase();
                    
                    updateProgress(1.0, 'Done.');
                  },
                ),
              ).then((_) {
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SignInScreen(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 400),
                    ),
                    (route) => false,
                  );
                }
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
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
                    labelText: 'Current PIN',
                    errorText: error ? 'Incorrect PIN' : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => setDialogState(() => newPin = v),
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: oldPin.length == 4 && newPin.length == 4
                    ? () async {
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        final success = await _authService.changePin(oldPin, newPin);
                        if (success) {
                          if (mounted) { navigator.pop(); }
                          if (mounted) { messenger.showSnackBar(
                            const SnackBar(content: Text('PIN changed successfully'), backgroundColor: AppColors.success),
                          ); }
                          
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));

    return ValueListenableBuilder<bool>(
      valueListenable: BackupFreshnessService.isReadOnlyMode,
      builder: (context, isReadOnly, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: GestureDetector(
              onTap: _handleSettingsTap,
              child: const Text('Settings'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
            children: [
              _sectionLabel('Security'),
              const SizedBox(height: 12),
              PremiumCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildSwitchTile(
                      icon: LucideIcons.lock,
                      title: 'App Lock',
                      subtitle: 'Secure app with PIN',
                      value: _isLockEnabled,
                      onChanged: isReadOnly ? null : _toggleLock,
                    ),
                    if (_isLockEnabled) ...[
                      Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity( 0.1)),
                      if (_hasBiometricHardware)
                        _buildSwitchTile(
                          icon: LucideIcons.fingerprint,
                          title: 'Biometrics',
                          subtitle: 'Unlock with fingerprint',
                          value: _isBiometricEnabled,
                          onChanged: isReadOnly ? null : _toggleBiometric,
                        ),
                      Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity( 0.1)),
                      _buildListTile(
                        icon: LucideIcons.key,
                        title: 'Change PIN',
                        onTap: isReadOnly ? null : _showChangePinDialog,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _sectionLabel('Display'),
              const SizedBox(height: 12),
              PremiumCard(
                padding: EdgeInsets.zero,
                child: Consumer<ThemeProvider>(
                  builder: (context, theme, _) => _buildSwitchTile(
                    icon: LucideIcons.moon,
                    title: 'Dark Mode',
                    subtitle: 'Enable dark theme',
                    value: theme.isDarkMode,
                    onChanged: isReadOnly ? null : (val) {
                      theme.toggleTheme(val);
                      
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _sectionLabel('Data & Backup'),
              const SizedBox(height: 12),
              PremiumCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: const Icon(LucideIcons.archive, color: AppColors.accent),
                      title: Text('Backup & Restore', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      subtitle: Text('Backup and restore options', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.7), fontSize: 12)),
                      trailing: Icon(LucideIcons.chevronRight, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.5)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Sign Out ────────────────────────────────────────────────
              _sectionLabel('Account'),
              const SizedBox(height: 12),
              PremiumCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading: const Icon(LucideIcons.logOut, color: AppColors.error),
                  title: const Text('Sign Out',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                  subtitle: const Text('You will need to sign in again to access the app',
                      style: TextStyle(fontSize: 12)),
                  onTap: isReadOnly ? null : _confirmSignOut,
                ),
              ),
              const SizedBox(height: 24),

              if (_developerModeEnabled) ...[
                _sectionLabel('Developer Tools'),
                const SizedBox(height: 12),
                PremiumCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        leading: _isGenerating 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                            : const Icon(LucideIcons.flaskConical, color: AppColors.accent),
                        title: const Text('Generate 500 Test Borrowers', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                        onTap: (isReadOnly || _isGenerating) ? null : _generateTestBorrowers,
                      ),
                      Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity( 0.1)),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        leading: const Icon(LucideIcons.trash2, color: AppColors.error),
                        title: const Text('Clear Local Database', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                        subtitle: const Text('Deletes all local records permanently', style: TextStyle(fontSize: 12)),
                        onTap: (isReadOnly || _isGenerating) ? null : () => _confirmClearLocalDatabase(context),
                      ),
                      Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity( 0.1)),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        leading: const Icon(LucideIcons.alertTriangle, color: AppColors.error),
                        title: const Text('Factory Reset App', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                        subtitle: const Text('Wipes local DB and settings', style: TextStyle(fontSize: 12)),
                        onTap: (isReadOnly || _isGenerating) ? null : () => _confirmFactoryReset(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
 
          Center(
            child: Text(
              'Credits v1.0.0',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity( 0.6), fontSize: 12),
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildSwitchTile({required IconData icon, required String title, required String subtitle, required bool value, required Function(bool)? onChanged}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: onChanged == null ? AppColors.accent.withOpacity(0.5) : AppColors.accent),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: onChanged == null ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5) : Theme.of(context).colorScheme.onSurface)),
      subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(onChanged == null ? 0.3 : 0.6), fontSize: 12)),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.accent,
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required String title, required VoidCallback? onTap, Color? color}) {
    final disabled = onTap == null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: disabled ? (color ?? AppColors.accent).withOpacity(0.5) : (color ?? AppColors.accent)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: disabled ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5) : color)),
      trailing: Icon(LucideIcons.chevronRight, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(disabled ? 0.3 : 0.6)),
      onTap: onTap,
    );
  }
}

