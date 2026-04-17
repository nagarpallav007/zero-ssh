import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Client-side zero-knowledge encryption.
///
/// Flow (once per session, at passphrase entry):
///   1. deriveMasterKey(passphrase, userSalt)  → SecretKey via Argon2id
///
/// Flow (per item, cheap):
///   2. encrypt(masterKey, plaintext)          → base64 blob "nonce:mac:cipher"
///   3. decrypt(masterKey, encryptedData)      → original plaintext
///
/// The passphrase never leaves the device. The server receives only the
/// encrypted blob; the user's salt is stored server-side on the User row.
class CryptoService {
  static final _aesGcm = AesGcm.with256bits();

  /// Derives a 32-byte master key from [passphrase] and a base64-encoded
  /// [userSalt] using Argon2id (memory=64 MB, iterations=3, parallelism=4).
  ///
  /// Called **once** per session at passphrase entry. The result is stored in
  /// [PassphraseManager] — all subsequent encrypt/decrypt calls use it directly
  /// with no further Argon2id work.
  static Future<SecretKey> deriveMasterKey(
      String passphrase, String userSalt) async {
    final saltBytes = base64.decode(userSalt);
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
  /// The nonce (IV) is randomly generated per call — safe to reuse the key.
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
      throw const FormatException(
          'Invalid encrypted data format: expected nonce:mac:ciphertext');
    }
    final nonce = base64.decode(parts[0]);
    final mac = Mac(base64.decode(parts[1]));
    final cipherText = base64.decode(parts[2]);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
  }
}

