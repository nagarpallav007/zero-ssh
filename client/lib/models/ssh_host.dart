import 'dart:convert';

/// An SSH host configuration.
///
/// Working fields (name, hostnameOrIp, etc.) are used at runtime for connections.
/// For server sync, all working fields are encrypted into [encryptedData] + [salt].
/// Local-only hosts (guest mode or the built-in local terminal) have null
/// [encryptedData] / [salt].
class SSHHost {
  final String id;
  final String name;
  final String hostnameOrIp;
  final String username;
  final int port;
  final String? keyId;
  final String? password;
  final String? keyFilePath;
  final String? privateKey;
  final String? publicKey;
  final bool isLocal;

  // Zero-knowledge sync fields — null for local-only / not yet synced hosts
  final String? encryptedData;
  final String? salt;

  SSHHost({
    required this.id,
    required this.name,
    required this.hostnameOrIp,
    required this.username,
    required this.port,
    this.keyId,
    this.password,
    this.keyFilePath,
    this.privateKey,
    this.publicKey,
    this.isLocal = false,
    this.encryptedData,
    this.salt,
  });

  SSHHost copyWith({
    String? id,
    String? name,
    String? hostnameOrIp,
    String? username,
    int? port,
    String? keyId,
    String? password,
    String? keyFilePath,
    String? privateKey,
    String? publicKey,
    bool? isLocal,
    String? encryptedData,
    String? salt,
  }) {
    return SSHHost(
      id: id ?? this.id,
      name: name ?? this.name,
      hostnameOrIp: hostnameOrIp ?? this.hostnameOrIp,
      username: username ?? this.username,
      port: port ?? this.port,
      keyId: keyId ?? this.keyId,
      password: password ?? this.password,
      keyFilePath: keyFilePath ?? this.keyFilePath,
      privateKey: privateKey ?? this.privateKey,
      publicKey: publicKey ?? this.publicKey,
      isLocal: isLocal ?? this.isLocal,
      encryptedData: encryptedData ?? this.encryptedData,
      salt: salt ?? this.salt,
    );
  }

  /// Serialize all working fields to JSON for local storage (SharedPreferences).
  factory SSHHost.fromJson(Map<String, dynamic> json) {
    return SSHHost(
      id: json['id'] as String,
      name: json['name'] as String,
      hostnameOrIp: json['hostnameOrIp'] as String,
      username: json['username'] as String,
      port: json['port'] as int,
      keyId: json['keyId'] as String?,
      password: json['password'] as String?,
      keyFilePath: json['keyFilePath'] as String?,
      privateKey: json['privateKey'] as String?,
      publicKey: json['publicKey'] as String?,
      isLocal: json['isLocal'] as bool? ?? false,
      encryptedData: json['encryptedData'] as String?,
      salt: json['salt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostnameOrIp': hostnameOrIp,
        'username': username,
        'port': port,
        'keyId': keyId,
        'password': password,
        'keyFilePath': keyFilePath,
        'privateKey': privateKey,
        'publicKey': publicKey,
        'isLocal': isLocal,
        'encryptedData': encryptedData,
        'salt': salt,
      };

  /// Returns a JSON map of all fields that should be encrypted before upload.
  /// This is the plaintext payload that the client encrypts client-side.
  Map<String, dynamic> toSyncPayload() => {
        'name': name,
        'hostnameOrIp': hostnameOrIp,
        'username': username,
        'port': port,
        'keyId': keyId,
        'password': password,
        'keyFilePath': keyFilePath,
        'privateKey': privateKey,
        'publicKey': publicKey,
        'isLocal': isLocal,
      };

  /// Restore working fields from decrypted server data.
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
      keyFilePath: json['keyFilePath'] as String?,
      privateKey: json['privateKey'] as String?,
      publicKey: json['publicKey'] as String?,
      isLocal: json['isLocal'] as bool? ?? false,
      encryptedData: encryptedData,
      salt: salt,
    );
  }

  /// Encode [toSyncPayload] as a JSON string ready for encryption.
  String toSyncJson() => jsonEncode(toSyncPayload());
}
