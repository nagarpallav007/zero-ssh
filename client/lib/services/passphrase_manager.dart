import 'package:cryptography/cryptography.dart';

/// In-memory master key store.
///
/// The master key is derived once at login time via Argon2id(passphrase, userSalt)
/// and held in memory for the duration of the session. It is NEVER written to
/// disk or transmitted over the network.
///
/// All subsequent encrypt/decrypt calls use this key directly via AES-256-GCM —
/// no further Argon2id calls are needed until the user logs out and back in.
///
/// On logout, call [clear] to wipe the key from memory.
class PassphraseManager {
  PassphraseManager._();

  static final PassphraseManager instance = PassphraseManager._();

  SecretKey? _masterKey;
  SimpleKeyPair? _keyPair;

  /// Store the derived master key for this session.
  void setMasterKey(SecretKey key) => _masterKey = key;

  /// Returns the master key, or null if not yet derived.
  SecretKey? get masterKey => _masterKey;

  /// True if the master key has been derived for this session.
  bool get isSet => _masterKey != null;

  /// Store the user's X25519 keypair for ECIES workspace key operations.
  void setKeyPair(SimpleKeyPair kp) => _keyPair = kp;

  /// Returns the X25519 keypair, or null if not yet set.
  SimpleKeyPair? get keyPair => _keyPair;

  /// Clears all in-memory secrets (call on logout).
  void clear() {
    _masterKey = null;
    _keyPair = null;
  }
}
