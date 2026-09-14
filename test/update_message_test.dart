import 'package:flutter_test/flutter_test.dart';
import 'package:credit/config/update_message.dart';
import 'package:credit/models/app_update_info.dart';

void main() {
  test('UpdateMessageConfig provides default values', () {
    expect(UpdateMessageConfig.title.isNotEmpty, isTrue);
    expect(UpdateMessageConfig.message.isNotEmpty, isTrue);
    expect(UpdateMessageConfig.releaseNotes.isNotEmpty, isTrue);

    final map = UpdateMessageConfig.toUpdateJson(
      buildNumber: 5,
      apkUrl: 'https://example.com/app.apk',
    );
    expect(map['buildNumber'], 5);
    expect(map['apkUrl'], 'https://example.com/app.apk');
    expect(map['title'], UpdateMessageConfig.title);
    expect(map['message'], UpdateMessageConfig.message);
    expect(map['releaseNotes'], UpdateMessageConfig.releaseNotes);
  });

  test('AppUpdateInfo parses title and message correctly', () {
    final json = {
      'buildNumber': 4,
      'apkUrl': 'https://example.com/app.apk',
      'title': 'Custom Update Title',
      'message': 'Custom update subtitle',
      'releaseNotes': [
        'Feature 1',
        'Feature 2',
      ],
    };

    final info = AppUpdateInfo.fromJson(json);
    expect(info.version, 4);
    expect(info.title, 'Custom Update Title');
    expect(info.message, 'Custom update subtitle');
    expect(info.releaseNotes, ['Feature 1', 'Feature 2']);
  });
}
