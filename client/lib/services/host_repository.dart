import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/ssh_host.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'crypto_service.dart';
import 'passphrase_manager.dart';
import 'storage_service.dart';

class HostRepository {
  HostRepository({required this.apiClient, required this.authService, StorageService? storage})
      : _storage = storage ?? StorageService();

  final ApiClient apiClient;
  final AuthService authService;
  final StorageService _storage;

  /// Loads hosts. If authenticated, fetches encrypted blobs from server and
  /// decrypts them locally. Falls back to local cache on error.
  Future<List<SSHHost>> loadHosts({bool forceRemote = false}) async {
    final session = await authService.currentSession();
    if (session == null && !forceRemote) {
      return _storage.loadHosts();
    }

    if (session != null) {
      try {
        final hosts = await _fetchAndDecryptHosts(session.token);
        await _storage.saveHosts(hosts);
        return hosts;
      } catch (_) {
        return _storage.loadHosts();
      }
    }

    return _storage.loadHosts();
  }

  /// Creates a host. If authenticated, encrypts with the master key and uploads.
  Future<SSHHost> createHost(SSHHost host) async {
    final session = await authService.currentSession();
    if (session == null) {
      final newHost = host.copyWith(id: const Uuid().v4());
      final hosts = await _storage.loadHosts();
      hosts.add(newHost);
      await _storage.saveHosts(hosts);
      return newHost;
    }

    final masterKey = PassphraseManager.instance.masterKey;
    if (masterKey == null) throw Exception('Passphrase required to sync hosts');

    final encryptedData = await CryptoService.encrypt(masterKey, host.toSyncJson());

    final res = await apiClient.postJson(
      '/hosts',
      {'encryptedData': encryptedData},
      token: session.token,
    );

    final serverData = res['host'] as Map<String, dynamic>;
    final created = host.copyWith(
      id: serverData['id'] as String,
      encryptedData: encryptedData,
    );
    await _syncCache(created);
    return created;
  }

  /// Updates a host. If authenticated, re-encrypts and uploads.
  Future<SSHHost> updateHost(SSHHost host) async {
    final session = await authService.currentSession();
    if (session == null) {
      final hosts = await _storage.loadHosts();
      final idx = hosts.indexWhere((h) => h.id == host.id);
      if (idx != -1) hosts[idx] = host;
      await _storage.saveHosts(hosts);
      return host;
    }

    final masterKey = PassphraseManager.instance.masterKey;
    if (masterKey == null) throw Exception('Passphrase required to sync hosts');

    final encryptedData = await CryptoService.encrypt(masterKey, host.toSyncJson());

    await apiClient.putJson(
      '/hosts/${host.id}',
      {'encryptedData': encryptedData},
      token: session.token,
    );

    final updated = host.copyWith(encryptedData: encryptedData);
    await _syncCache(updated);
    return updated;
  }

  Future<void> deleteHost(String id) async {
    final session = await authService.currentSession();
    if (session == null) {
      final hosts = await _storage.loadHosts();
      hosts.removeWhere((h) => h.id == id);
      await _storage.saveHosts(hosts);
      return;
    }

    await apiClient.delete('/hosts/$id', token: session.token);
    final hosts = await _storage.loadHosts();
    hosts.removeWhere((h) => h.id == id);
    await _storage.saveHosts(hosts);
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<List<SSHHost>> _fetchAndDecryptHosts(String token) async {
    final masterKey = PassphraseManager.instance.masterKey;
    final data = await apiClient.getJson('/hosts', token: token);
    final rawList = data['hosts'] as List<dynamic>? ?? [];

    final List<SSHHost> hosts = [];
    for (final e in rawList) {
      final json = e as Map<String, dynamic>;
      final id = json['id'] as String;
      final encryptedData = json['encryptedData'] as String;

      if (masterKey == null) continue;

      try {
        final plainJson = await CryptoService.decrypt(masterKey, encryptedData);
        final decoded = jsonDecode(plainJson) as Map<String, dynamic>;
        hosts.add(SSHHost.fromDecryptedJson(id, decoded, encryptedData: encryptedData));
      } catch (_) {
        // Decryption failure — skip this host
      }
    }
    return hosts;
  }

  Future<void> _syncCache(SSHHost host) async {
    final hosts = await _storage.loadHosts();
    final idx = hosts.indexWhere((h) => h.id == host.id);
    if (idx == -1) {
      hosts.add(host);
    } else {
      hosts[idx] = host;
    }
    await _storage.saveHosts(hosts);
  }
}
