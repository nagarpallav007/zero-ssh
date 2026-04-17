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

  /// Store the derived master key for this session.
  void setMasterKey(SecretKey key) => _masterKey = key;

  /// Returns the master key, or null if not yet derived.
  SecretKey? get masterKey => _masterKey;

  /// True if the master key has been derived for this session.
  bool get isSet => _masterKey != null;

  /// Clears the master key from memory (call on logout).
  void clear() => _masterKey = null;
}
