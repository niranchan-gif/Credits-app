import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit/models/app_update_info.dart';
import 'package:credit/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateInfo Parsing Tests', () {
    test('Correctly parses GitHub update.json format (camelCase)', () {
      const jsonString = '''
      {
        "buildNumber": 5,
        "apkUrl": "https://github.com/niranchan-gif/Credits-app/releases/download/Creditsv3/app-release.apk",
        "releaseNotes": "Bug fixes and performance improvements."
      }
      ''';
      final map = json.decode(jsonString) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(map);

      expect(info.buildNumber, 5);
      expect(info.version, 5);
      expect(info.downloadUrl, 'https://github.com/niranchan-gif/Credits-app/releases/download/Creditsv3/app-release.apk');
      expect(info.releaseNotes, ['Bug fixes and performance improvements.']);
      expect(info.forceUpdate, true); // default true when not specified
    });

    test('Correctly parses multiline release notes', () {
      const jsonString = '''
      {
        "buildNumber": 6,
        "apkUrl": "https://example.com/app.apk",
        "releaseNotes": "New dashboard\\nFaster sync\\nFixed crash"
      }
      ''';
      final map = json.decode(jsonString) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(map);

      expect(info.buildNumber, 6);
      expect(info.releaseNotes, ['New dashboard', 'Faster sync', 'Fixed crash']);
    });

    test('Correctly parses legacy / snake_case format', () {
      const jsonString = '''
      {
        "version": 7,
        "download_url": "https://example.com/legacy.apk",
        "release_notes": ["Feature A", "Feature B"],
        "force_update": false
      }
      ''';
      final map = json.decode(jsonString) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(map);

      expect(info.buildNumber, 7);
      expect(info.downloadUrl, 'https://example.com/legacy.apk');
      expect(info.releaseNotes, ['Feature A', 'Feature B']);
      expect(info.forceUpdate, false);
    });

    test('Handles string build numbers gracefully', () {
      const jsonString = '''
      {
        "buildNumber": "8",
        "apkUrl": "https://example.com/app.apk"
      }
      ''';
      final map = json.decode(jsonString) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(map);

      expect(info.buildNumber, 8);
    });
  });

  group('Update Logic Difference Detection Tests', () {
    test('No update triggered when local build equals remote build', () {
      final remoteInfo = AppUpdateInfo(
        version: 5,
        forceUpdate: true,
        downloadUrl: 'https://example.com/app.apk',
      );
      const int localBuild = 5;

      UpdateStatus status = UpdateStatus.upToDate;
      if (remoteInfo.buildNumber != localBuild) {
        status = remoteInfo.forceUpdate ? UpdateStatus.mandatoryUpdate : UpdateStatus.optionalUpdate;
      }

      expect(status, UpdateStatus.upToDate);
    });

    test('Mandatory update triggered when remote build is different from local build', () {
      final remoteInfo = AppUpdateInfo(
        version: 6,
        forceUpdate: true,
        downloadUrl: 'https://example.com/app.apk',
      );
      const int localBuild = 5;

      UpdateStatus status = UpdateStatus.upToDate;
      if (remoteInfo.buildNumber != localBuild) {
        status = remoteInfo.forceUpdate ? UpdateStatus.mandatoryUpdate : UpdateStatus.optionalUpdate;
      }

      expect(status, UpdateStatus.mandatoryUpdate);
    });
  });
}
