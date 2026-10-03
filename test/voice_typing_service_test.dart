import 'package:flutter_test/flutter_test.dart';
import 'package:credit/services/voice_typing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceTypingService', () {
    final service = VoiceTypingService.instance;

    test('defaults to Tamil language (ta_IN)', () {
      expect(service.currentLocaleId, 'ta_IN');
      expect(service.isTamil, isTrue);
      expect(service.languageLabel, 'தமிழ்');
      expect(service.languageDisplayName, contains('தமிழ்'));
    });

    test('manual locale setting works', () {
      service.setLocale('en_IN');
      expect(service.isTamil, isFalse);
      expect(service.languageLabel, 'EN');
      expect(service.languageDisplayName, contains('English'));

      // Restore Tamil
      service.setLocale('ta_IN');
      expect(service.isTamil, isTrue);
      expect(service.languageLabel, 'தமிழ்');
    });
  });
}
