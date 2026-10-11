import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Optional account/version telemetry for Credits.
///
/// This is intentionally independent from GoogleDriveService. It must never
/// be used to grant access to local data or to initialize/modify Drive backup.
class FirebaseUserMonitorService {
  FirebaseUserMonitorService._();

  static final FirebaseUserMonitorService instance =
      FirebaseUserMonitorService._();

  bool _initialized = false;
  bool _monitoringEnabled = true;

  /// Best-effort initialization. Firebase monitoring failures never affect app
  /// startup, local storage, Google Drive sign-in, or backup/restore.
  Future<void> initialize() async {
    if (_initialized || !_monitoringEnabled) return;

    try {
      // FirebaseOptions are normally supplied by FlutterFire-generated
      // firebase_options.dart. This fallback supports platforms where native
      // Firebase configuration is installed. If no config exists, fail closed.
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp();
        } catch (error) {
          debugPrint('Firebase monitor unavailable; continuing offline: $error');
          return;
        }
      }

      _initialized = true;
    } catch (error) {
      debugPrint('Firebase monitor initialization failed: $error');
    }
  }

  /// Sign in with Google for telemetry only. Does not request Drive scopes and
  /// does not sign out or mutate GoogleDriveService's account.
  ///
  /// Call this only from an explicit user action after the app explains that
  /// this is a separate monitoring identity. It is deliberately not invoked
  /// automatically from the existing Google Drive sign-in button.
  Future<void> recordMonitoringIdentity(User user) async {
    if (!_initialized || !_monitoringEnabled) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final now = FieldValue.serverTimestamp();
      final ref = FirebaseFirestore.instance
          .collection('credits_app_users')
          .doc(user.uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final old = snapshot.data();

        transaction.set(
          ref,
          <String, dynamic>{
            'uid': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'photoUrl': user.photoURL,
            'provider': 'google.com',
            'appVersion': info.version,
            'buildNumber': info.buildNumber,
            'platform': _platformName,
            'lastSeenAt': now,
            'updatedAt': now,
            if (!snapshot.exists) 'firstSeenAt': now,
            if (old?['createdAt'] == null) 'createdAt': now,
          },
          SetOptions(merge: true),
        );
      });

      await FirebaseFirestore.instance
          .collection('credits_app_sessions')
          .add(<String, dynamic>{
        'uid': user.uid,
        'appVersion': info.version,
        'buildNumber': info.buildNumber,
        'platform': _platformName,
        'startedAt': now,
      });
    } catch (error) {
      // Monitoring is best-effort and must not surface as a sign-in failure.
      debugPrint('Firebase monitor could not record usage: $error');
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Disable telemetry locally for the current process if needed.
  void disableForCurrentRun() => _monitoringEnabled = false;
}
