import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/foundation.dart';
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
    final int currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;
    final String currentVersion = packageInfo.version;

    AppUpdateInfo? updateInfo;

    try {
      // Short timeout for offline-first design
      final response = await http.get(Uri.parse(_updateJsonUrl)).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final jsonMap = json.decode(response.body);
        updateInfo = AppUpdateInfo.fromJson(jsonMap);
        
        // Cache it for offline checks later
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
        currentVersion: currentVersion,
        currentBuild: currentBuild,
      );
    }

    UpdateStatus status = UpdateStatus.upToDate;

    if (currentBuild < updateInfo.version) {
      final prefs = await SharedPreferences.getInstance();
      final skippedVersion = prefs.getInt('skipped_update_version') ?? 0;
      
      if (skippedVersion == updateInfo.version) {
        status = UpdateStatus.upToDate;
      } else {
        status = updateInfo.forceUpdate ? UpdateStatus.mandatoryUpdate : UpdateStatus.optionalUpdate;
      }
    }

    return UpdateCheckResult(
      status: status,
      updateInfo: updateInfo,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  Future<void> downloadAndInstallApk(String url, Function(double) onProgress) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download APK. Status: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;

      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationSupportDirectory();
      }
      
      if (dir == null) throw Exception('Cannot access storage');
      
      final file = File('${dir.path}/credits_update.apk');
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0) {
          onProgress(downloadedBytes / contentLength);
        }
      }

      await sink.close();
      
      // Install
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception('Failed to open APK: ${result.message}');
      }
    } catch (e) {
      debugPrint('Download/Install error: $e');
      rethrow;
    }
  }
}
