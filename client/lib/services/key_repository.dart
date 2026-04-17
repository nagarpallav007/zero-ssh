import '../models/ssh_key.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'crypto_service.dart';
import 'passphrase_manager.dart';

class KeyRepository {
  KeyRepository({required this.apiClient, required this.authService});

  final ApiClient apiClient;
  final AuthService authService;

  /// Fetches all keys from the server and decrypts them using the master key.
  /// Returns an empty list if the user is not logged in or master key is not set.
  Future<List<SSHKey>> loadKeys() async {
    final session = await authService.currentSession();
    if (session == null) return [];

    final masterKey = PassphraseManager.instance.masterKey;

    final res = await apiClient.getJson('/keys', token: session.token);
    final list = (res['keys'] as List<dynamic>? ?? [])
        .map((e) => SSHKey.fromApiJson(e as Map<String, dynamic>))
        .toList();

    if (masterKey != null) {
      for (final key in list) {
        try {
          key.decryptedPrivateKey = await CryptoService.decrypt(
            masterKey,
            key.encryptedData,
          );
        } catch (_) {
          // Decryption failure — leave null.
        }
      }
    }

    return list;
  }

  /// Encrypts [privateKey] with the master key and uploads to the server.
  Future<SSHKey> addKey(String label, String privateKey, {String? publicKey}) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required to save keys');

    final masterKey = PassphraseManager.instance.masterKey;
    if (masterKey == null) throw Exception('Passphrase required to save keys');

    final encryptedData = await CryptoService.encrypt(masterKey, privateKey);

    final res = await apiClient.postJson(
      '/keys',
      {
        'label': label,
        'publicKey': publicKey,
        'encryptedData': encryptedData,
      },
      token: session.token,
    );

    final key = SSHKey.fromApiJson(res['key'] as Map<String, dynamic>);
    key.decryptedPrivateKey = privateKey;
    return key;
  }

  /// Re-encrypts [privateKey] and updates the server record.
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
      final masterKey = PassphraseManager.instance.masterKey;
      if (masterKey == null) throw Exception('Passphrase required to update key');
      body['encryptedData'] = await CryptoService.encrypt(masterKey, privateKey);
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
