import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace.dart';
import 'api_client.dart';

class AuthSession {
  final String token;
  final String email;
  final String userSalt;         // Argon2id salt for master key derivation
  final String? publicKey;       // X25519 public key (not sensitive, persisted)
  final String? encryptedPrivateKey; // X25519 private key encrypted with masterKey (transient)
  final String plan;             // 'free' | 'trial' | 'pro'
  final List<WorkspaceSession> workspaces;

  AuthSession({
    required this.token,
    required this.email,
    required this.userSalt,
    this.publicKey,
    this.encryptedPrivateKey,
    this.plan = 'free',
    this.workspaces = const [],
  });

  WorkspaceSession? get defaultWorkspace =>
      workspaces.where((w) => w.isDefault).firstOrNull;
}

class AuthService {
  AuthService({required this.apiClient});

  final ApiClient apiClient;

  static const _tokenKey     = 'auth_token';
  static const _emailKey     = 'auth_email';
  static const _saltKey      = 'auth_user_salt';
  static const _publicKeyKey = 'auth_public_key';
  static const _planKey      = 'auth_plan';
  static const _workspacesKey = 'auth_workspaces';

  Future<AuthSession?> currentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token  = prefs.getString(_tokenKey);
    final email  = prefs.getString(_emailKey);
    final salt   = prefs.getString(_saltKey);
    if (token == null || email == null || salt == null) return null;

    final publicKey  = prefs.getString(_publicKeyKey);
    final plan       = prefs.getString(_planKey) ?? 'free';
    final wsJson     = prefs.getString(_workspacesKey);
    final workspaces = wsJson != null
        ? (jsonDecode(wsJson) as List<dynamic>)
            .map((e) => WorkspaceSession.fromJson(e as Map<String, dynamic>))
            .toList()
        : <WorkspaceSession>[];

    // encryptedPrivateKey is NOT persisted — it's transient per login
    return AuthSession(
      token: token,
      email: email,
      userSalt: salt,
      publicKey: publicKey,
      plan: plan,
      workspaces: workspaces,
    );
  }

  Future<AuthSession> signup(String email, String password) async {
    final res = await apiClient.postJson('/auth/signup', {
      'email': email,
      'password': password,
    });
    return _persistSession(res);
  }

  Future<AuthSession> login(String email, String password) async {
    final res = await apiClient.postJson('/auth/login', {
      'email': email,
      'password': password,
    });
    return _persistSession(res);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_publicKeyKey);
    await prefs.remove(_planKey);
    await prefs.remove(_workspacesKey);
  }

  /// Overwrites the full workspaces list in SharedPreferences.
  /// Called when a fresh list is fetched from the server and the cached one is stale.
  Future<void> saveWorkspacesCache(List<WorkspaceSession> workspaces) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _workspacesKey, jsonEncode(workspaces.map((w) => w.toJson()).toList()));
  }

  /// Updates the encryptedWorkspaceKey for a specific workspace in the persisted
  /// session. Called after uploading a newly-generated workspace key so that
  /// cold restarts can decrypt it without a fresh login.
  Future<void> updateWorkspaceKeyCache(
      String workspaceId, String encryptedWorkspaceKey) async {
    final prefs = await SharedPreferences.getInstance();
    final wsJson = prefs.getString(_workspacesKey);
    if (wsJson == null) return;
    final workspaces = (jsonDecode(wsJson) as List<dynamic>)
        .map((e) => WorkspaceSession.fromJson(e as Map<String, dynamic>))
        .toList();
    final updated = workspaces.map((w) {
      if (w.id != workspaceId) return w;
      return WorkspaceSession(
        id: w.id,
        name: w.name,
        isDefault: w.isDefault,
        role: w.role,
        encryptedWorkspaceKey: encryptedWorkspaceKey,
        inviteStatus: w.inviteStatus,
      );
    }).toList();
    await prefs.setString(
        _workspacesKey, jsonEncode(updated.map((w) => w.toJson()).toList()));
  }

  Future<AuthSession> _persistSession(Map<String, dynamic> res) async {
    final token    = res['token'] as String?;
    final userSalt = res['userSalt'] as String?;
    final user     = res['user'] as Map<String, dynamic>?;
    if (token == null || userSalt == null || user == null) {
      throw Exception('Invalid auth response');
    }
    final email              = user['email'] as String? ?? '';
    final publicKey          = res['publicKey'] as String?;
    final encryptedPrivateKey = res['encryptedPrivateKey'] as String?;
    final plan               = res['plan'] as String? ?? 'free';
    final rawWorkspaces      = res['workspaces'] as List<dynamic>? ?? [];
    final workspaces = rawWorkspaces
        .map((e) => WorkspaceSession.fromJson(e as Map<String, dynamic>))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
    await prefs.setString(_saltKey, userSalt);
    if (publicKey != null) await prefs.setString(_publicKeyKey, publicKey);
    await prefs.setString(_planKey, plan);
    // Persist workspaces without encryptedWorkspaceKey (re-fetched on login)
    // but keep encryptedWorkspaceKey for offline cold-start use
    await prefs.setString(_workspacesKey, jsonEncode(workspaces.map((w) => w.toJson()).toList()));

    return AuthSession(
      token: token,
      email: email,
      userSalt: userSalt,
      publicKey: publicKey,
      encryptedPrivateKey: encryptedPrivateKey, // transient, not persisted
      plan: plan,
      workspaces: workspaces,
    );
  }
}
