class AppUpdateInfo {
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;

  AppUpdateInfo({
    required this.buildNumber,
    required this.apkUrl,
    this.releaseNotes = '',
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      buildNumber: json['buildNumber'] as int? ?? 1,
      apkUrl: json['apkUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buildNumber': buildNumber,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
    };
  }
}
