import 'package:uuid/uuid.dart';

import '../models/ssh_host.dart';
import 'auth_service.dart';
import 'storage_service.dart';
import 'workspace_repository.dart';

class HostRepository {
  HostRepository({
    required this.authService,
    required this.workspaceRepository,
    StorageService? storage,
  }) : _storage = storage ?? StorageService();

  final AuthService authService;
  final WorkspaceRepository workspaceRepository;
  final StorageService _storage;

  Future<String?> _defaultWorkspaceId() async {
    return workspaceRepository.getDefaultWorkspaceId();
  }

  Future<List<SSHHost>> loadHosts({bool forceRemote = false}) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) return _storage.loadHosts();
    try {
      final hosts = await workspaceRepository.loadWorkspaceHosts(wsId);
      await _storage.saveHosts(hosts);
      return hosts;
    } catch (_) {
      return _storage.loadHosts();
    }
  }

  Future<SSHHost> createHost(SSHHost host) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) {
      final newHost = host.copyWith(id: const Uuid().v4());
      final hosts = await _storage.loadHosts();
      hosts.add(newHost);
      await _storage.saveHosts(hosts);
      return newHost;
    }
    final saved = await workspaceRepository.createWorkspaceHost(wsId, host);
    await _syncCache(saved);
    return saved;
  }

  Future<SSHHost> updateHost(SSHHost host) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) {
      final hosts = await _storage.loadHosts();
      final idx = hosts.indexWhere((h) => h.id == host.id);
      if (idx != -1) hosts[idx] = host;
      await _storage.saveHosts(hosts);
      return host;
    }
    final updated = await workspaceRepository.updateWorkspaceHost(wsId, host);
    await _syncCache(updated);
    return updated;
  }

  Future<void> deleteHost(String id) async {
    final wsId = await _defaultWorkspaceId();
    if (wsId == null) {
      final hosts = await _storage.loadHosts();
      hosts.removeWhere((h) => h.id == id);
      await _storage.saveHosts(hosts);
      return;
    }
    await workspaceRepository.deleteWorkspaceHost(wsId, id);
    final hosts = await _storage.loadHosts();
    hosts.removeWhere((h) => h.id == id);
    await _storage.saveHosts(hosts);
  }

  Future<void> clearCache() => _storage.clearHosts();

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
