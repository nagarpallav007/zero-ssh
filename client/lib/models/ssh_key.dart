/// An SSH key pair stored on the server as an encrypted blob.
///
/// The server stores [encryptedData] + [salt] and has no way to decrypt them.
/// After the client decrypts, the plaintext private key is held in
/// [decryptedPrivateKey] (in memory only — never serialized or uploaded).
class SSHKey {
  final String id;
  final String? label;
  final String? publicKey;
  final String encryptedData; // AES-256-GCM ciphertext from server
  final String salt;          // Argon2id salt (base64) from server
  String? decryptedPrivateKey; // populated after client-side decryption

  SSHKey({
    required this.id,
    this.label,
    this.publicKey,
    required this.encryptedData,
    required this.salt,
    this.decryptedPrivateKey,
  });

  factory SSHKey.fromApiJson(Map<String, dynamic> json) => SSHKey(
        id: json['id'] as String,
        label: json['label'] as String?,
        publicKey: json['publicKey'] as String?,
        encryptedData: json['encryptedData'] as String,
        salt: json['salt'] as String,
      );

  Map<String, dynamic> toUploadPayload({String? publicKey}) => {
        'label': label,
        'publicKey': publicKey ?? this.publicKey,
        'encryptedData': encryptedData,
        'salt': salt,
      };
}
