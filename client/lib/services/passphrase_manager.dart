/// In-memory passphrase store.
///
/// The passphrase is NEVER written to disk, stored in SharedPreferences,
/// flutter_secure_storage, or transmitted over the network.
/// It lives only in this singleton for the duration of the app session.
/// On logout, call [clear] to wipe it from memory.
class PassphraseManager {
  PassphraseManager._();

  static final PassphraseManager instance = PassphraseManager._();

  String? _passphrase;

  /// Set the passphrase for this session.
  void set(String passphrase) => _passphrase = passphrase;

  /// Returns the passphrase, or null if not yet set.
  String? get() => _passphrase;

  /// True if the passphrase has been entered for this session.
  bool get isSet => _passphrase != null;

  /// Clears the passphrase from memory (call on logout).
  void clear() => _passphrase = null;
}
