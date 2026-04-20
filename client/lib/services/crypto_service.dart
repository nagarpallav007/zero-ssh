import 'dart:convert';
import 'dart:math';

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

  // ── ECIES (X25519 + HKDF-SHA256 + AES-256-GCM) ────────────────────────────

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _hkdfInfo = utf8.encode('zerossh-workspace-key');

  /// Generates a new X25519 keypair for the calling user.
  static Future<SimpleKeyPair> generateKeyPair() => _x25519.newKeyPair();

  /// Generates a random 32-byte workspace key and returns it as a [SecretKey].
  static SecretKey generateWorkspaceKey() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return SecretKey(bytes);
  }

  /// ECIES-encrypts [plaintext] for a recipient whose X25519 public key bytes
  /// are given as base64 in [recipientPublicKeyB64].
  /// Returns a 4-part string: `ephPubB64:nonce:mac:cipher`.
  static Future<String> eciesEncrypt(
    SimplePublicKey recipientPublicKey,
    String plaintext,
  ) async {
    // 1. Ephemeral keypair
    final ephPair = await _x25519.newKeyPair();
    final ephPub = await ephPair.extractPublicKey();

    // 2. Shared secret via ECDH
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephPair,
      remotePublicKey: recipientPublicKey,
    );

    // 3. Derive encryption key via HKDF
    final encKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: const [],
      info: _hkdfInfo,
    );

    // 4. AES-256-GCM encrypt
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: encKey,
    );

    final ephPubB64 = base64.encode(ephPub.bytes);
    final nonceB64 = base64.encode(secretBox.nonce);
    final macB64 = base64.encode(secretBox.mac.bytes);
    final cipherB64 = base64.encode(secretBox.cipherText);
    return '$ephPubB64:$nonceB64:$macB64:$cipherB64';
  }

  /// ECIES-decrypts a 4-part string produced by [eciesEncrypt] using [myKeyPair].
  static Future<String> eciesDecrypt(
    SimpleKeyPair myKeyPair,
    String encryptedData,
  ) async {
    final parts = encryptedData.split(':');
    if (parts.length != 4) {
      throw const FormatException('Invalid ECIES format: expected ephPub:nonce:mac:cipher');
    }

    final ephPub = SimplePublicKey(
      base64.decode(parts[0]),
      type: KeyPairType.x25519,
    );

    // 1. Shared secret
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: ephPub,
    );

    // 2. Derive same encryption key
    final encKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: const [],
      info: _hkdfInfo,
    );

    // 3. AES-256-GCM decrypt
    final nonce = base64.decode(parts[1]);
    final mac = Mac(base64.decode(parts[2]));
    final cipherText = base64.decode(parts[3]);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: encKey);
    return utf8.decode(plainBytes);
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

