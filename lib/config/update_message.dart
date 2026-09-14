/// ============================================================================
/// UPDATE MESSAGE CONFIGURATION
/// ============================================================================
/// This file is used to configure and customize the message displayed in the
/// App Update Screen ("Update Tab").
///
/// Whenever you want to change what users see when an update is available,
/// simply edit the title, message, and list of release notes below!
/// ============================================================================

class UpdateMessageConfig {
  /// The main headline shown at the top of the update screen.
  static const String title = 'Upgrade to the new version of our app';

  /// Subtitle or header text shown above the feature checklist.
  static const String message = "What's new in this update:";

  /// The bullet points / checklist items shown on the update screen.
  /// Add, remove, or modify any items in this list.
  static const List<String> releaseNotes = [
    "Quick Add: Tap today's total to view all transactions for that date",
    "Fixed layout gap at the top of the tabs",
    "General stability and performance improvements",
  ];

  /// Helper to export this configuration into JSON format matching `update.json`.
  static Map<String, dynamic> toUpdateJson({
    required int buildNumber,
    required String apkUrl,
    bool forceUpdate = true,
  }) {
    return {
      'buildNumber': buildNumber,
      'apkUrl': apkUrl,
      'forceUpdate': forceUpdate,
      'title': title,
      'message': message,
      'releaseNotes': releaseNotes,
    };
  }
}
