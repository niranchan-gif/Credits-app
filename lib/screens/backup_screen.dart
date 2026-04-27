import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/loan_provider.dart';
import '../services/firebase_bootstrap.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _registerMode = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await task();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginOrRegister() async {
    await _runBusy(() async {
      await FirebaseBootstrap.init();
      if (!FirebaseBootstrap.isInitialized) {
        throw Exception(
            'Firebase is not configured. Add firebase_options.dart or platform config files first.');
      }

      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (email.isEmpty || password.length < 6) {
        throw Exception('Enter email and password with at least 6 characters.');
      }

      if (_registerMode) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    });
  }

  Future<void> _backupNow() async {
    final provider = context.read<LoanProvider>();
    await _runBusy(() async {
      await FirebaseBootstrap.init();
      if (!FirebaseBootstrap.isInitialized) {
        throw Exception(
            'Firebase is not configured. Add firebase_options.dart or platform config files first.');
      }

      await provider.backupNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Backup completed.'),
        backgroundColor: Colors.green,
      ));
    });
  }

  Future<void> _logout() async {
    final provider = context.read<LoanProvider>();
    await _runBusy(() async {
      await provider.logoutAndClearLocalCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Backup', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder(
        future: FirebaseBootstrap.init(),
        builder: (context, _) {
          final firebaseReady = FirebaseBootstrap.isInitialized;
          return StreamBuilder<User?>(
            stream:
                firebaseReady ? FirebaseAuth.instance.authStateChanges() : null,
            builder: (context, snapshot) {
              final user = snapshot.data;
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  if (!FirebaseBootstrap.isInitialized)
                    _warningCard(
                      'Firebase setup needed',
                      'Run FlutterFire configuration and add your Firebase files. The app code is ready, but backup cannot connect yet.',
                    ),
                  if (user == null) ...[
                    _sectionTitle(_registerMode ? 'Create Login' : 'Login'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _loginOrRegister,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_registerMode
                              ? Icons.person_add_alt_1
                              : Icons.login),
                      label: Text(_registerMode ? 'Create Account' : 'Login'),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () =>
                              setState(() => _registerMode = !_registerMode),
                      child: Text(_registerMode
                          ? 'Already have an account? Login'
                          : 'New user? Create account'),
                    ),
                  ] else ...[
                    _sectionTitle('Cloud Backup'),
                    const SizedBox(height: 8),
                    _infoCard('Logged in as', user.email ?? user.uid),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _backupNow,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Backup Now'),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1E3A5F),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      );

  Widget _warningCard(String title, String body) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orangeAccent),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.deepOrange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _infoCard(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
