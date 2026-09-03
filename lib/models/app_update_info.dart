class AppUpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final String minimumVersion;
  final int minimumBuild;
  final bool forceUpdate;
  final String downloadUrl;
  final List<String> releaseNotes;

  AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumVersion,
    required this.minimumBuild,
    required this.forceUpdate,
    required this.downloadUrl,
    this.releaseNotes = const [],
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      latestVersion: json['latest_version'] as String? ?? '1.0.0',
      latestBuild: json['latest_build'] as int? ?? 1,
      minimumVersion: json['minimum_version'] as String? ?? '1.0.0',
      minimumBuild: json['minimum_build'] as int? ?? 1,
      forceUpdate: json['force_update'] as bool? ?? false,
      downloadUrl: json['download_url'] as String? ?? '',
      releaseNotes: (json['release_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latest_version': latestVersion,
      'latest_build': latestBuild,
      'minimum_version': minimumVersion,
      'minimum_build': minimumBuild,
      'force_update': forceUpdate,
      'download_url': downloadUrl,
      'release_notes': releaseNotes,
    };
  }
}
