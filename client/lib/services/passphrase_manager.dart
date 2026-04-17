/// In-memory passphrase store.
///
/// The passphrase is NEVER written to disk, stored in SharedPreferences,
/// flutter_secure_storage, or transmitted over the network.
/// It lives only in this singleton for the duration of the app session.
/// On logout, call [clear] to wipe it from memory.
///
/// Derived AES keys are also cached here (keyed by salt) so that
/// Argon2id is only run once per host per session rather than once per
/// host per load. The cache is cleared on logout alongside the passphrase.
class PassphraseManager {
  PassphraseManager._();

  static final PassphraseManager instance = PassphraseManager._();

  String? _passphrase;

  // Derived key cache: salt (base64) → raw key bytes.
  // Avoids re-running Argon2id for the same salt on every reload.
  final Map<String, List<int>> _keyCache = {};

  /// Set the passphrase for this session.
  void set(String passphrase) => _passphrase = passphrase;

  /// Returns the passphrase, or null if not yet set.
  String? get() => _passphrase;

  /// True if the passphrase has been entered for this session.
  bool get isSet => _passphrase != null;

  /// Returns cached derived key bytes for [salt], or null if not yet derived.
  List<int>? cachedKeyBytes(String salt) => _keyCache[salt];

  /// Stores derived key bytes for [salt].
  void cacheKeyBytes(String salt, List<int> bytes) => _keyCache[salt] = bytes;

  /// Clears the passphrase and all derived key material from memory (call on logout).
  void clear() {
    _passphrase = null;
    _keyCache.clear();
  }
}
