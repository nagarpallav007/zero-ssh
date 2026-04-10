import '../models/ssh_key.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'crypto_service.dart';
import 'passphrase_manager.dart';

class KeyRepository {
  KeyRepository({required this.apiClient, required this.authService});

  final ApiClient apiClient;
  final AuthService authService;

  /// Fetches all keys from the server and decrypts them using the in-memory passphrase.
  /// Returns an empty list if the user is not logged in or passphrase is not set.
  Future<List<SSHKey>> loadKeys() async {
    final session = await authService.currentSession();
    if (session == null) return [];

    final passphrase = PassphraseManager.instance.get();

    final res = await apiClient.getJson('/keys', token: session.token);
    final list = (res['keys'] as List<dynamic>? ?? [])
        .map((e) => SSHKey.fromApiJson(e as Map<String, dynamic>))
        .toList();

    if (passphrase != null) {
      for (final key in list) {
        try {
          key.decryptedPrivateKey = await CryptoService.decryptWithPassphrase(
            passphrase,
            key.encryptedData,
            key.salt,
          );
        } catch (_) {
          // Decryption failure (wrong passphrase or corrupt data) — leave null.
        }
      }
    }

    return list;
  }

  /// Encrypts [privateKey] with the current passphrase and uploads to the server.
  Future<SSHKey> addKey(String label, String privateKey, {String? publicKey}) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required to save keys');

    final passphrase = PassphraseManager.instance.get();
    if (passphrase == null) throw Exception('Passphrase required to save keys');

    final (:encryptedData, :salt) =
        await CryptoService.encryptWithPassphrase(passphrase, privateKey);

    final res = await apiClient.postJson(
      '/keys',
      {
        'label': label,
        'publicKey': publicKey,
        'encryptedData': encryptedData,
        'salt': salt,
      },
      token: session.token,
    );

    final key = SSHKey.fromApiJson(res['key'] as Map<String, dynamic>);
    key.decryptedPrivateKey = privateKey;
    return key;
  }

  /// Re-encrypts [privateKey] with a fresh salt and updates the server record.
  Future<SSHKey> updateKey(
    String id, {
    String? label,
    String? privateKey,
    String? publicKey,
  }) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');

    final body = <String, dynamic>{};
    if (label != null) body['label'] = label;
    if (publicKey != null) body['publicKey'] = publicKey;

    if (privateKey != null) {
      final passphrase = PassphraseManager.instance.get();
      if (passphrase == null) throw Exception('Passphrase required to update key');
      final (:encryptedData, :salt) =
          await CryptoService.encryptWithPassphrase(passphrase, privateKey);
      body['encryptedData'] = encryptedData;
      body['salt'] = salt;
    }

    final res = await apiClient.putJson('/keys/$id', body, token: session.token);
    final key = SSHKey.fromApiJson(res['key'] as Map<String, dynamic>);
    if (privateKey != null) key.decryptedPrivateKey = privateKey;
    return key;
  }

  /// Deletes a key from the server.
  Future<void> deleteKey(String id) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    await apiClient.delete('/keys/$id', token: session.token);
  }
}
