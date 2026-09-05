import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _cacheKey = 'cached_update_info';
  
  Future<UpdateCheckResult> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    
    // Read the local update.json to get the bundled build number
    int currentBuild = 1;
    try {
      final localJsonString = await rootBundle.loadString('update.json');
      final localJsonMap = json.decode(localJsonString);
      currentBuild = localJsonMap['version'] as int? ?? 1;
    } catch (e) {
      debugPrint('Failed to read local update.json: $e');
      currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1; // Fallback
    }

    // Bypass updates in debug mode so it doesn't loop during development
    if (kDebugMode) {
      return UpdateCheckResult(
        status: UpdateStatus.upToDate,
        currentVersion: packageInfo.version,
        currentBuild: currentBuild,
      );
    }

    AppUpdateInfo? updateInfo;

    try {
      final response = await http.get(
        Uri.parse(_updateJsonUrl),
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final jsonMap = json.decode(response.body);
        updateInfo = AppUpdateInfo.fromJson(jsonMap);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, json.encode(jsonMap));
      }
    } catch (e) {
      debugPrint('Update check failed: $e, falling back to cache');
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString(_cacheKey);
      if (cachedString != null) {
        try {
          updateInfo = AppUpdateInfo.fromJson(json.decode(cachedString));
        } catch (e) {
          debugPrint('Failed to parse cached update info: $e');
        }
      }
    }

    if (updateInfo == null) {
      return UpdateCheckResult(
        status: UpdateStatus.upToDate, 
        currentVersion: packageInfo.version,
        currentBuild: currentBuild,
      );
    }

    UpdateStatus status = UpdateStatus.upToDate;

    // Check if remote version is strictly greater than installed build
    if (currentBuild < updateInfo.version) {
      if (updateInfo.forceUpdate) {
        status = UpdateStatus.mandatoryUpdate;
      } else {
        status = UpdateStatus.optionalUpdate;
      }
    }

    return UpdateCheckResult(
      status: status,
      updateInfo: updateInfo,
      currentVersion: packageInfo.version,
      currentBuild: currentBuild,
    );
  }
}
