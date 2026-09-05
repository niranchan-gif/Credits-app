class AppUpdateInfo {
  final int version;
  final bool forceUpdate;
  final String downloadUrl;
  final List<String> releaseNotes;

  AppUpdateInfo({
    required this.version,
    required this.forceUpdate,
    required this.downloadUrl,
    this.releaseNotes = const [],
  });

  int get buildNumber => version;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    List<String> notes = [];
    final rawNotes = json['releaseNotes'] ?? json['release_notes'] ?? json['notes'];
    if (rawNotes != null) {
      if (rawNotes is List) {
        notes = List<String>.from(rawNotes.map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
      } else if (rawNotes is String) {
        final lines = rawNotes.split('\n').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
        notes = lines.isNotEmpty ? lines : [rawNotes.trim()];
      }
    }

    final rawBuild = json['buildNumber'] ?? json['version'] ?? json['build_number'];
    int parsedBuild = 1;
    if (rawBuild is int) {
      parsedBuild = rawBuild;
    } else if (rawBuild is String) {
      parsedBuild = int.tryParse(rawBuild) ?? 1;
    }

    final rawUrl = json['apkUrl'] ?? json['download_url'] ?? json['downloadUrl'] ?? json['apk_url'] ?? json['url'] ?? '';

    final rawForce = json['forceUpdate'] ?? json['force_update'];
    bool parsedForce = true;
    if (rawForce is bool) {
      parsedForce = rawForce;
    }

    return AppUpdateInfo(
      version: parsedBuild,
      forceUpdate: parsedForce,
      downloadUrl: rawUrl.toString().trim(),
      releaseNotes: notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buildNumber': version,
      'version': version,
      'forceUpdate': forceUpdate,
      'apkUrl': downloadUrl,
      'download_url': downloadUrl,
      'releaseNotes': releaseNotes,
    };
  }
}
