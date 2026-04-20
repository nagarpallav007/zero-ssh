import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../models/ssh_host.dart';
import '../models/ssh_key.dart';
import '../models/workspace.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'crypto_service.dart';
import 'passphrase_manager.dart';

class WorkspaceRepository {
  WorkspaceRepository({required this.apiClient, required this.authService});

  final ApiClient apiClient;
  final AuthService authService;

  /// In-memory cache of decrypted workspace keys: workspaceId → SecretKey
  final Map<String, SecretKey> _keyCache = {};

  // ── Key management ────────────────────────────────────────────────────────

  /// Cache a workspace key directly (used by PassphrasePage for the default workspace).
  void cacheWorkspaceKey(String workspaceId, SecretKey key) {
    _keyCache[workspaceId] = key;
  }

  /// Get (and cache) the workspace key. Decrypts via ECIES on first access.
  Future<SecretKey> getWorkspaceKey(String workspaceId, String encryptedWorkspaceKey) async {
    if (_keyCache.containsKey(workspaceId)) return _keyCache[workspaceId]!;

    final keyPair = PassphraseManager.instance.keyPair;
    if (keyPair == null) throw Exception('Keypair not set — passphrase required');

    final keyB64 = await CryptoService.eciesDecrypt(keyPair, encryptedWorkspaceKey);
    final key = SecretKey(base64.decode(keyB64));
    _keyCache[workspaceId] = key;
    return key;
  }

  void clearCache() => _keyCache.clear();

  // ── Workspace CRUD ────────────────────────────────────────────────────────

  Future<List<WorkspaceSession>> loadWorkspaces() async {
    final session = await authService.currentSession();
    if (session == null) return [];
    final res = await apiClient.getJson('/workspaces', token: session.token);
    return (res['workspaces'] as List<dynamic>? ?? [])
        .map((e) => WorkspaceSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the default workspace ID, fetching from the API and refreshing
  /// SharedPreferences if the cached session has no workspaces (stale after migration).
  Future<String?> getDefaultWorkspaceId() async {
    final session = await authService.currentSession();
    if (session == null) return null;

    // Fast path: cached workspaces are populated
    final cached = session.workspaces.where((w) => w.isDefault).firstOrNull;
    if (cached != null) return cached.id;

    // Slow path: stale cache — fetch from API and persist
    try {
      final workspaces = await loadWorkspaces();
      await authService.saveWorkspacesCache(workspaces);
      return workspaces.where((w) => w.isDefault).firstOrNull?.id;
    } catch (_) {
      return null;
    }
  }

  Future<WorkspaceSession> createWorkspace(String name) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');

    final keyPair = PassphraseManager.instance.keyPair;
    if (keyPair == null) throw Exception('Keypair not set');

    // Generate workspace key and ECIES-encrypt for self
    final wsKey = CryptoService.generateWorkspaceKey();
    final myPub = await keyPair.extractPublicKey();
    final wsKeyB64 = base64.encode(await wsKey.extractBytes());
    final encryptedWorkspaceKey = await CryptoService.eciesEncrypt(myPub, wsKeyB64);

    final res = await apiClient.postJson(
      '/workspaces',
      {'name': name, 'encryptedWorkspaceKey': encryptedWorkspaceKey},
      token: session.token,
    );

    final ws = res['workspace'] as Map<String, dynamic>;
    final wsSession = WorkspaceSession(
      id: ws['id'] as String,
      name: ws['name'] as String,
      isDefault: false,
      role: WorkspaceRole.owner,
      encryptedWorkspaceKey: encryptedWorkspaceKey,
      inviteStatus: 'accepted',
    );

    _keyCache[wsSession.id] = wsKey;
    return wsSession;
  }

  Future<WorkspaceDetail> loadWorkspaceDetail(String workspaceId) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    final res = await apiClient.getJson('/workspaces/$workspaceId', token: session.token);

    final workspace = Workspace.fromJson(res['workspace'] as Map<String, dynamic>);
    final members = (res['members'] as List<dynamic>? ?? [])
        .map((e) => WorkspaceMember.fromJson(e as Map<String, dynamic>))
        .toList();
    final encryptedWorkspaceKey = res['encryptedWorkspaceKey'] as String?;

    return WorkspaceDetail(
      workspace: workspace,
      members: members,
      encryptedWorkspaceKey: encryptedWorkspaceKey,
    );
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    await apiClient.delete('/workspaces/$workspaceId', token: session.token);
    _keyCache.remove(workspaceId);
  }

  // ── Members ───────────────────────────────────────────────────────────────

  Future<WorkspaceMember> inviteMember(
    String workspaceId,
    String email,
    WorkspaceRole role,
    String encryptedWorkspaceKey,
  ) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');

    // Lookup invitee's public key
    final lookup = await apiClient.getJson(
      '/users/lookup?email=${Uri.encodeQueryComponent(email)}',
      token: session.token,
    );
    final inviteePublicKeyB64 = lookup['publicKey'] as String;
    final inviteePub = SimplePublicKey(
      base64.decode(inviteePublicKeyB64),
      type: KeyPairType.x25519,
    );

    // ECIES-encrypt workspace key for invitee
    final wsKey = _keyCache[workspaceId];
    if (wsKey == null) throw Exception('Workspace key not cached — load workspace first');
    final wsKeyB64 = base64.encode(await wsKey.extractBytes());
    final encryptedForInvitee = await CryptoService.eciesEncrypt(inviteePub, wsKeyB64);

    final res = await apiClient.postJson(
      '/workspaces/$workspaceId/invites',
      {
        'email': email,
        'encryptedWorkspaceKey': encryptedForInvitee,
        'role': role.value,
      },
      token: session.token,
    );

    return WorkspaceMember.fromJson(res['member'] as Map<String, dynamic>);
  }

  /// Removes a member and atomically rotates the workspace key.
  /// Requires all current workspace hosts and keys to re-encrypt.
  Future<void> removeMember(
    String workspaceId,
    String targetUserId,
    WorkspaceDetail detail,
  ) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');

    final oldKey = _keyCache[workspaceId];
    if (oldKey == null) throw Exception('Workspace key not cached');

    // Generate new workspace key
    final newKey = CryptoService.generateWorkspaceKey();
    final newKeyB64 = base64.encode(await newKey.extractBytes());

    // Re-encrypt all hosts
    final hosts = await loadWorkspaceHosts(workspaceId);
    final rotatedHosts = await Future.wait(hosts.map((h) async {
      final newEncData = await CryptoService.encrypt(newKey, h.toSyncJson());
      return {'id': h.id, 'encryptedData': newEncData};
    }));

    // Re-encrypt all keys
    final keys = await loadWorkspaceKeys(workspaceId);
    final rotatedKeys = await Future.wait(keys.map((k) async {
      final plaintext = k.decryptedPrivateKey ?? '';
      final newEncData = await CryptoService.encrypt(newKey, plaintext);
      return {'id': k.id, 'encryptedData': newEncData};
    }));

    // ECIES-encrypt new key for each remaining accepted member
    final remainingMembers = detail.members
        .where((m) => m.userId != targetUserId && m.inviteStatus == 'accepted' && m.publicKey != null)
        .toList();

    final newMemberKeys = await Future.wait(remainingMembers.map((m) async {
      final pub = SimplePublicKey(base64.decode(m.publicKey!), type: KeyPairType.x25519);
      final enc = await CryptoService.eciesEncrypt(pub, newKeyB64);
      return {'userId': m.userId, 'encryptedWorkspaceKey': enc};
    }));

    await apiClient.deleteWithBody(
      '/workspaces/$workspaceId/members/$targetUserId',
      {
        'rotatedHosts': rotatedHosts,
        'rotatedKeys': rotatedKeys,
        'newMemberKeys': newMemberKeys,
      },
      token: session.token,
    );

    _keyCache[workspaceId] = newKey;
  }

  Future<void> updateMemberRole(
    String workspaceId,
    String userId,
    WorkspaceRole role,
  ) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    await apiClient.putJson(
      '/workspaces/$workspaceId/members/$userId',
      {'role': role.value},
      token: session.token,
    );
  }

  // ── Hosts ─────────────────────────────────────────────────────────────────

  Future<List<SSHHost>> loadWorkspaceHosts(String workspaceId) async {
    final session = await authService.currentSession();
    if (session == null) return [];

    final wsSession = session.workspaces.where((w) => w.id == workspaceId).firstOrNull;
    final encKey = wsSession?.encryptedWorkspaceKey;
    if (encKey == null && !_keyCache.containsKey(workspaceId)) return [];

    final workspaceKey = _keyCache[workspaceId] ??
        await getWorkspaceKey(workspaceId, encKey!);

    final res = await apiClient.getJson('/workspaces/$workspaceId/hosts', token: session.token);
    final rawList = res['hosts'] as List<dynamic>? ?? [];

    final List<SSHHost> hosts = [];
    for (final e in rawList) {
      final json = e as Map<String, dynamic>;
      final id = json['id'] as String;
      final encryptedData = json['encryptedData'] as String;
      try {
        final plain = await CryptoService.decrypt(workspaceKey, encryptedData);
        final decoded = jsonDecode(plain) as Map<String, dynamic>;
        hosts.add(SSHHost.fromDecryptedJson(id, decoded, encryptedData: encryptedData));
      } catch (_) {
        // Decryption failure — skip
      }
    }
    return hosts;
  }

  Future<SSHHost> createWorkspaceHost(String workspaceId, SSHHost host) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    final workspaceKey = _keyCache[workspaceId] ?? (throw Exception('Workspace key not cached'));

    final encryptedData = await CryptoService.encrypt(workspaceKey, host.toSyncJson());
    final res = await apiClient.postJson(
      '/workspaces/$workspaceId/hosts',
      {'encryptedData': encryptedData},
      token: session.token,
    );
    final row = res['host'] as Map<String, dynamic>;
    return SSHHost.fromDecryptedJson(
      row['id'] as String,
      jsonDecode(host.toSyncJson()) as Map<String, dynamic>,
      encryptedData: encryptedData,
    );
  }

  Future<SSHHost> updateWorkspaceHost(String workspaceId, SSHHost host) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    final workspaceKey = _keyCache[workspaceId] ?? (throw Exception('Workspace key not cached'));

    final encryptedData = await CryptoService.encrypt(workspaceKey, host.toSyncJson());
    await apiClient.putJson(
      '/workspaces/$workspaceId/hosts/${host.id}',
      {'encryptedData': encryptedData},
      token: session.token,
    );
    return host.copyWith(encryptedData: encryptedData);
  }

  Future<void> deleteWorkspaceHost(String workspaceId, String hostId) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    await apiClient.delete('/workspaces/$workspaceId/hosts/$hostId', token: session.token);
  }

  // ── Keys ──────────────────────────────────────────────────────────────────

  Future<List<SSHKey>> loadWorkspaceKeys(String workspaceId) async {
    final session = await authService.currentSession();
    if (session == null) return [];

    final wsSession = session.workspaces.where((w) => w.id == workspaceId).firstOrNull;
    final encKey = wsSession?.encryptedWorkspaceKey;
    if (encKey == null && !_keyCache.containsKey(workspaceId)) return [];

    final workspaceKey = _keyCache[workspaceId] ??
        await getWorkspaceKey(workspaceId, encKey!);

    final res = await apiClient.getJson('/workspaces/$workspaceId/keys', token: session.token);
    final list = (res['keys'] as List<dynamic>? ?? [])
        .map((e) => SSHKey.fromApiJson(e as Map<String, dynamic>))
        .toList();

    for (final key in list) {
      try {
        key.decryptedPrivateKey = await CryptoService.decrypt(workspaceKey, key.encryptedData);
      } catch (_) {}
    }
    return list;
  }

  Future<SSHKey> createWorkspaceKey(
    String workspaceId,
    String privateKey, {
    String? label,
    String? publicKey,
  }) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    final workspaceKey = _keyCache[workspaceId] ?? (throw Exception('Workspace key not cached'));

    final encryptedData = await CryptoService.encrypt(workspaceKey, privateKey);
    final res = await apiClient.postJson(
      '/workspaces/$workspaceId/keys',
      {'label': label, 'publicKey': publicKey, 'encryptedData': encryptedData},
      token: session.token,
    );
    final key = SSHKey.fromApiJson(res['key'] as Map<String, dynamic>);
    key.decryptedPrivateKey = privateKey;
    return key;
  }

  Future<SSHKey> updateWorkspaceKey(
    String workspaceId,
    String keyId, {
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
      final workspaceKey = _keyCache[workspaceId] ?? (throw Exception('Workspace key not cached'));
      body['encryptedData'] = await CryptoService.encrypt(workspaceKey, privateKey);
    }

    final res = await apiClient.putJson(
      '/workspaces/$workspaceId/keys/$keyId',
      body,
      token: session.token,
    );
    final key = SSHKey.fromApiJson(res['key'] as Map<String, dynamic>);
    if (privateKey != null) key.decryptedPrivateKey = privateKey;
    return key;
  }

  Future<void> deleteWorkspaceKey(String workspaceId, String keyId) async {
    final session = await authService.currentSession();
    if (session == null) throw Exception('Login required');
    await apiClient.delete('/workspaces/$workspaceId/keys/$keyId', token: session.token);
  }
}
