import '../models/ssh_key.dart';
import 'auth_service.dart';
import 'workspace_repository.dart';

class KeyRepository {
  KeyRepository({
    required this.authService,
    required this.workspaceRepository,
    this.fixedWorkspaceId,
  });

  final AuthService authService;
  final WorkspaceRepository workspaceRepository;

  /// If set, always use this workspace ID instead of the default workspace.
  final String? fixedWorkspaceId;

  Future<String?> _defaultWorkspaceId() async {
    if (fixedWorkspaceId != null) return fixedWorkspaceId;
    return workspaceRepository.getDefaultWorkspaceId();
  }

  Future<List<SSHKey>> loadKeys() async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) return [];
    return workspaceRepository.loadWorkspaceKeys(wsId);
  }

  Future<SSHKey> addKey(String label, String privateKey, {String? publicKey}) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) throw Exception('Login required to save keys');
    return workspaceRepository.createWorkspaceKey(
      wsId,
      privateKey,
      label: label,
      publicKey: publicKey,
    );
  }

  Future<SSHKey> updateKey(
    String id, {
    String? label,
    String? privateKey,
    String? publicKey,
  }) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) throw Exception('Login required');
    return workspaceRepository.updateWorkspaceKey(
      wsId,
      id,
      label: label,
      privateKey: privateKey,
      publicKey: publicKey,
    );
  }

  Future<void> deleteKey(String id) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) throw Exception('Login required');
    await workspaceRepository.deleteWorkspaceKey(wsId, id);
  }
}
