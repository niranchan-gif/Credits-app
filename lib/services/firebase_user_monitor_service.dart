import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'google_drive_service.dart';

/// Best-effort user/version monitoring, separate from Credits' data and backup
/// backend. It reuses the Google account already used by Google Drive and
/// never prompts for another sign-in or requests additional Google scopes.
class FirebaseUserMonitorService {
  FirebaseUserMonitorService._();

  static final FirebaseUserMonitorService instance =
      FirebaseUserMonitorService._();

  bool _initialized = false;
  bool _initializationAttempted = false;

  /// Initializes the default Firebase app. Firebase configuration is supplied
  /// by the platform configuration (for Android: google-services.json).
  /// Missing config simply disables monitoring; it never blocks app startup.
  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_initializationAttempted) return false;
    _initializationAttempted = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _initialized = true;
      return true;
    } catch (error) {
      debugPrint('Credits Firebase monitoring unavailable: $error');
      return false;
    }
  }

  /// Records the currently connected Drive account after the existing
  /// sign-in completed successfully. This is best-effort and does not affect
  /// the Drive sign-in / restore result.
  Future<void> trackGoogleAccount(GoogleSignInAccount account) async {
    try {
      if (!await initialize()) return;
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        debugPrint('Credits Firebase monitoring skipped: no Google access token.');
        return;
      }
      await _signInAndRecord(token);
    } catch (error) {
      debugPrint('Credits Firebase monitoring failed (ignored): $error');
    }
  }

  /// Refreshes the existing Google session silently on startup, then updates
  /// the current user's last-seen time and installed version.
  Future<void> trackCurrentDriveAccount() async {
    try {
      if (!await initialize()) return;
      final token = await GoogleDriveService().getMonitoringAccessToken();
      if (token == null || token.isEmpty) return;
      await _signInAndRecord(token);
    } catch (error) {
      debugPrint('Credits Firebase startup monitoring failed (ignored): $error');
    }
  }

  Future<void> _signInAndRecord(String accessToken) async {
    final credential = GoogleAuthProvider.credential(accessToken: accessToken);
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = result.user;
    if (user == null) return;

    final info = await PackageInfo.fromPlatform();
    final now = FieldValue.serverTimestamp();
    final userRef = FirebaseFirestore.instance
        .collection('credits_app_users')
        .doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final oldData = snapshot.data();

      transaction.set(
        userRef,
        <String, dynamic>{
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'provider': 'google.com',
          'appVersion': info.version,
          'buildNumber': info.buildNumber,
          'platform': _platformName,
          'lastSeenAt': now,
          'updatedAt': now,
          if (!snapshot.exists) 'firstSeenAt': now,
          if (oldData?['createdAt'] == null) 'createdAt': now,
        },
        SetOptions(merge: true),
      );
    });
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }
}
