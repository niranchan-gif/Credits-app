import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/app_update_info.dart';

enum UpdateStatus {
  upToDate,
  optionalUpdate,
  mandatoryUpdate,
}

class UpdateCheckResult {
  final UpdateStatus status;
  final AppUpdateInfo? updateInfo;
  final String currentVersion;
  final int currentBuild;

  UpdateCheckResult({
    required this.status,
    this.updateInfo,
    required this.currentVersion,
    required this.currentBuild,
  });
}

class UpdateService {
  static const String _updateJsonUrl = 'https://raw.githubusercontent.com/niranchan-gif/Credits-app/main/update.json';
  
  Future<UpdateCheckResult> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    
    // 1. Read the local bundled update.json to get the mobile app's installed build number
    int currentBuild = 1;
    try {
      final localJsonString = await rootBundle.loadString('update.json');
      final localJsonMap = json.decode(localJsonString);
      final rawBuild = localJsonMap['buildNumber'] ?? localJsonMap['version'] ?? localJsonMap['build_number'];
      if (rawBuild is int) {
        currentBuild = rawBuild;
      } else if (rawBuild is String) {
        currentBuild = int.tryParse(rawBuild) ?? 1;
      }
    } catch (e) {
      debugPrint('UpdateService: Could not read local update.json, using packageInfo: $e');
      currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;
    }

    AppUpdateInfo? updateInfo;

    // 2. Fetch the remote update.json from GitHub with cache-busting & short timeout
    try {
      final cacheBusterUri = Uri.parse('$_updateJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(
        cacheBusterUri,
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final jsonMap = json.decode(response.body);
        if (jsonMap is Map<String, dynamic>) {
          updateInfo = AppUpdateInfo.fromJson(jsonMap);
        }
      } else {
        debugPrint('UpdateService: Non-200 HTTP status (${response.statusCode}). Allowing app entry.');
        return UpdateCheckResult(
          status: UpdateStatus.upToDate,
          currentVersion: packageInfo.version,
          currentBuild: currentBuild,
        );
      }
    } catch (e) {
      // If there is an error, network failure, or timeout, gracefully allow the user to enter the app
      debugPrint('UpdateService: Network failure or error checking update: $e. Allowing app entry.');
      return UpdateCheckResult(
        status: UpdateStatus.upToDate,
        currentVersion: packageInfo.version,
        currentBuild: currentBuild,
      );
    }

    if (updateInfo == null) {
      return UpdateCheckResult(
        status: UpdateStatus.upToDate, 
        currentVersion: packageInfo.version,
        currentBuild: currentBuild,
      );
    }

    final remoteBuild = updateInfo.buildNumber;
    debugPrint('UpdateService: Local build=$currentBuild, GitHub remote build=$remoteBuild');

    UpdateStatus status = UpdateStatus.upToDate;

    // 3. Check if there is any difference between the mobile app build and GitHub build
    if (remoteBuild != currentBuild) {
      status = updateInfo.forceUpdate ? UpdateStatus.mandatoryUpdate : UpdateStatus.optionalUpdate;
    }

    return UpdateCheckResult(
      status: status,
      updateInfo: updateInfo,
      currentVersion: packageInfo.version,
      currentBuild: currentBuild,
    );
  }
}
