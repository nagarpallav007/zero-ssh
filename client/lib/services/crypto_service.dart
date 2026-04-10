import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Client-side zero-knowledge encryption.
///
/// Flow:
///   1. generateSalt()                     → random 16-byte base64 salt
///   2. deriveKey(passphrase, salt)        → 32-byte key via Argon2id
///   3. encrypt(key, plaintext)            → base64 blob "nonce:mac:cipher"
///   4. decrypt(key, encryptedData)        → original plaintext
///
/// The passphrase never leaves the device. The server receives only
/// the encrypted blob and the salt — it cannot derive the key.
class CryptoService {
  static final _aesGcm = AesGcm.with256bits();

  /// Generates a cryptographically random 16-byte salt encoded as base64.
  static String generateSalt() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    return base64.encode(bytes);
  }

  /// Derives a 32-byte AES key from [passphrase] and a base64-encoded [salt]
  /// using Argon2id (memory=64 MB, iterations=3, parallelism=4).
  static Future<SecretKey> deriveKey(String passphrase, String salt) async {
    final saltBytes = base64.decode(salt);
    final algorithm = Argon2id(
      parallelism: 4,
      memory: 65536, // 64 MB
      iterations: 3,
      hashLength: 32,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: saltBytes,
    );
  }

  /// AES-256-GCM encrypts [plaintext] using [key].
  /// Returns a base64 string in the format "nonce:mac:ciphertext".
  static Future<String> encrypt(SecretKey key, String plaintext) async {
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    final nonceB64 = base64.encode(secretBox.nonce);
    final macB64 = base64.encode(secretBox.mac.bytes);
    final cipherB64 = base64.encode(secretBox.cipherText);
    return '$nonceB64:$macB64:$cipherB64';
  }

  /// AES-256-GCM decrypts [encryptedData] (format "nonce:mac:ciphertext") using [key].
  static Future<String> decrypt(SecretKey key, String encryptedData) async {
    final parts = encryptedData.split(':');
    if (parts.length != 3) {
      throw const FormatException('Invalid encrypted data format: expected nonce:mac:ciphertext');
    }
    final nonce = base64.decode(parts[0]);
    final mac = Mac(base64.decode(parts[1]));
    final cipherText = base64.decode(parts[2]);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
  }

  /// Convenience: derive key from [passphrase] + new salt, then encrypt [plaintext].
  /// Returns a record with the encrypted blob and the salt (both needed to decrypt).
  static Future<({String encryptedData, String salt})> encryptWithPassphrase(
    String passphrase,
    String plaintext,
  ) async {
    final salt = generateSalt();
    final key = await deriveKey(passphrase, salt);
    final encryptedData = await encrypt(key, plaintext);
    return (encryptedData: encryptedData, salt: salt);
  }

  /// Convenience: derive key from [passphrase] + stored [salt], then decrypt.
  static Future<String> decryptWithPassphrase(
    String passphrase,
    String encryptedData,
    String salt,
  ) async {
    final key = await deriveKey(passphrase, salt);
    return decrypt(key, encryptedData);
  }
}
