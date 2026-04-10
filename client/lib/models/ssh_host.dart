import 'dart:convert';

/// An SSH host configuration.
///
/// Sensitive fields (password, keyId) are encrypted into [encryptedData]+[salt]
/// before being uploaded to the server. The server stores only the opaque blob.
///
/// [privateKey] is TRANSIENT — it is never stored or synced. It is resolved
/// at connection time from the [keyId] reference in the keys table.
class SSHHost {
  final String id;
  final String name; // display label
  final String hostnameOrIp;
  final String username;
  final int port;
  final String? keyId; // reference to a saved key in the keys table
  final String? password;
  final bool isLocal;

  // Zero-knowledge sync fields — null for local-only hosts
  final String? encryptedData;
  final String? salt;

  // Transient: resolved from keyId at connection time, never stored or synced
  String? privateKey;

  SSHHost({
    required this.id,
    required this.name,
    required this.hostnameOrIp,
    required this.username,
    required this.port,
    this.keyId,
    this.password,
    this.isLocal = false,
    this.encryptedData,
    this.salt,
    this.privateKey,
  });

  SSHHost copyWith({
    String? id,
    String? name,
    String? hostnameOrIp,
    String? username,
    int? port,
    String? keyId,
    String? password,
    bool? isLocal,
    String? encryptedData,
    String? salt,
    String? privateKey,
  }) {
    return SSHHost(
      id: id ?? this.id,
      name: name ?? this.name,
      hostnameOrIp: hostnameOrIp ?? this.hostnameOrIp,
      username: username ?? this.username,
      port: port ?? this.port,
      keyId: keyId ?? this.keyId,
      password: password ?? this.password,
      isLocal: isLocal ?? this.isLocal,
      encryptedData: encryptedData ?? this.encryptedData,
      salt: salt ?? this.salt,
      privateKey: privateKey ?? this.privateKey,
    );
  }

  /// Restore from local SharedPreferences cache (no privateKey stored).
  factory SSHHost.fromJson(Map<String, dynamic> json) {
    return SSHHost(
      id: json['id'] as String,
      name: json['name'] as String,
      hostnameOrIp: json['hostnameOrIp'] as String,
      username: json['username'] as String,
      port: json['port'] as int,
      keyId: json['keyId'] as String?,
      password: json['password'] as String?,
      isLocal: json['isLocal'] as bool? ?? false,
      encryptedData: json['encryptedData'] as String?,
      salt: json['salt'] as String?,
    );
  }

  /// Serialise for local cache — no privateKey, no keyFilePath.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostnameOrIp': hostnameOrIp,
        'username': username,
        'port': port,
        'keyId': keyId,
        'password': password,
        'isLocal': isLocal,
        'encryptedData': encryptedData,
        'salt': salt,
      };

  /// Fields that get encrypted and uploaded to the server.
  /// Only keyId is stored as the key reference — no raw private key.
  Map<String, dynamic> toSyncPayload() => {
        'name': name,
        'hostnameOrIp': hostnameOrIp,
        'username': username,
        'port': port,
        'keyId': keyId,
        'password': password,
        'isLocal': isLocal,
      };

  /// Encode [toSyncPayload] as a JSON string ready for AES-GCM encryption.
  String toSyncJson() => jsonEncode(toSyncPayload());

  /// Restore working fields from decrypted server blob.
  factory SSHHost.fromDecryptedJson(
    String serverId,
    Map<String, dynamic> json, {
    String? encryptedData,
    String? salt,
  }) {
    return SSHHost(
      id: serverId,
      name: json['name'] as String? ?? 'Host',
      hostnameOrIp: json['hostnameOrIp'] as String? ?? '',
      username: json['username'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      keyId: json['keyId'] as String?,
      password: json['password'] as String?,
      isLocal: json['isLocal'] as bool? ?? false,
      encryptedData: encryptedData,
      salt: salt,
    );
  }
}
