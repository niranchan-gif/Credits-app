import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
class EncryptionService {
  /// Generates a highly secure 32-byte AES key by taking a SHA-256 hash from:
  ///   - Google account email (or a static offline fallback)
  ///   - Device identifier (derived consistently from Platform.operatingSystem to guarantee cross-device restore)
  ///   - App secret seed
  static enc.Key generateAESKey({String? email, String? deviceIdentifier}) {
    final cleanEmail = (email != null && email.isNotEmpty) ? email : 'offline_user@credits.app';
    final cleanDevice = (deviceIdentifier != null && deviceIdentifier.isNotEmpty)
        ? deviceIdentifier
        : Platform.operatingSystem;
    const appSecretSeed = 'CrEdItSaPpBaCkUpSeCuReKeY2026##AppSecretSeed';

    final combinedString = '$cleanEmail|$cleanDevice|$appSecretSeed';
    final keyBytes = sha256.convert(utf8.encode(combinedString)).bytes;

    // Safety verification: key must be exactly 32 bytes (256 bits) for AES-256
    assert(keyBytes.length == 32, 'AES-256 key must be exactly 32 bytes');

    return enc.Key(Uint8List.fromList(keyBytes));
  }

  /// Encrypts bytes using AES-256-CBC with a secure random IV.
  /// Prepends the 16-byte IV to the resulting ciphertext.
  static List<int> encryptBytes(List<int> plainBytes, {String? email, String? deviceIdentifier}) {
    try {
      final key = generateAESKey(email: email, deviceIdentifier: deviceIdentifier);
      
      // Verification asserts
      assert(key.length == 32, 'AES-256 key must be exactly 32 bytes');

      final iv = enc.IV.fromSecureRandom(16);
      assert(iv.bytes.length == 16, 'AES-CBC IV must be exactly 16 bytes');

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      
      // Combine 16-byte IV + ciphertext
      final result = Uint8List(16 + encrypted.bytes.length);
      result.setRange(0, 16, iv.bytes);
      result.setRange(16, result.length, encrypted.bytes);
      return result;
    } catch (e) {
      throw Exception('Backup encryption initialization failed: $e');
    }
  }

  /// Decrypts bytes that were encrypted using [encryptBytes].
  /// Extracts the 16-byte IV from the prepended bytes to decrypt the remaining ciphertext.
  static List<int> decryptBytes(List<int> cipherBytes, {String? email, String? deviceIdentifier}) {
    try {
      if (cipherBytes.length < 16) {
        throw Exception('Corrupted backup file: data is too short');
      }
      
      final key = generateAESKey(email: email, deviceIdentifier: deviceIdentifier);
      
      // Verification asserts
      assert(key.length == 32, 'AES-256 key must be exactly 32 bytes');

      final ivBytes = Uint8List.sublistView(Uint8List.fromList(cipherBytes), 0, 16);
      final encryptedBytes = Uint8List.sublistView(Uint8List.fromList(cipherBytes), 16);
      
      final iv = enc.IV(ivBytes);
      assert(iv.bytes.length == 16, 'AES-CBC IV must be exactly 16 bytes');

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);
      return decrypted;
    } catch (e) {
      throw Exception('Backup decryption failed. The file may be corrupted, or the encryption credentials are invalid.');
    }
  }
}

