import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class BackupEncryptionService {
  /// Generates a highly secure 32-byte AES key using the Google Account ID.
  /// This guarantees that Android and Windows compute the exact same encryption key 
  /// for the same Google user, allowing seamless cross-platform restores without weakening device encryption.
  static enc.Key _generateBackupKey(String googleAccountId) {
    if (googleAccountId.trim().isEmpty) {
      throw Exception('Backup encryption failed: Google Account ID is missing.');
    }
    
    // The googleAccountId binds the backup to the authorized user.
    const appSecretSalt = 'CreditsCdbBackupSecretSalt2026_V1';
    final combinedString = '$googleAccountId|$appSecretSalt';
    
    final keyBytes = sha256.convert(utf8.encode(combinedString)).bytes;
    assert(keyBytes.length == 32, 'AES-256 key must be exactly 32 bytes');
    
    return enc.Key(Uint8List.fromList(keyBytes));
  }

  static List<int> encryptBytes(List<int> plainBytes, String googleAccountId) {
    try {
      final key = _generateBackupKey(googleAccountId);
      final iv = enc.IV.fromSecureRandom(16);
      
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
      
      final result = Uint8List(16 + encrypted.bytes.length);
      result.setRange(0, 16, iv.bytes);
      result.setRange(16, result.length, encrypted.bytes);
      return result;
    } catch (e) {
      throw Exception('CDB Encryption failed: $e');
    }
  }

  static List<int> decryptBytes(List<int> cipherBytes, String googleAccountId) {
    try {
      if (cipherBytes.length < 16) {
        throw Exception('Corrupted CDB backup file: data is too short');
      }
      
      final key = _generateBackupKey(googleAccountId);
      
      final ivBytes = Uint8List.sublistView(Uint8List.fromList(cipherBytes), 0, 16);
      final encryptedBytes = Uint8List.sublistView(Uint8List.fromList(cipherBytes), 16);
      
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      
      return encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);
    } catch (e) {
      throw Exception('CDB Decryption failed. The file may be corrupted, or the Google account does not match.');
    }
  }
}
