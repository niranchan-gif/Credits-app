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

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    List<String> notes = [];
    if (json['release_notes'] != null) {
      if (json['release_notes'] is List) {
        notes = List<String>.from(json['release_notes']);
      } else if (json['release_notes'] is String) {
        notes = [json['release_notes'] as String];
      }
    }

    return AppUpdateInfo(
      version: json['version'] as int? ?? 1,
      forceUpdate: json['force_update'] as bool? ?? false,
      downloadUrl: json['download_url'] as String? ?? '',
      releaseNotes: notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'force_update': forceUpdate,
      'download_url': downloadUrl,
      'release_notes': releaseNotes,
    };
  }
}
