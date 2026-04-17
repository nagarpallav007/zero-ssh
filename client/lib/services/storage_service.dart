import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ssh_host.dart';

class StorageService {
  static const String _key = 'ssh_hosts';

  Future<List<SSHHost>> loadHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => SSHHost.fromJson(e)).toList();
  }

  Future<void> saveHosts(List<SSHHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(hosts.map((e) => e.toJson()).toList());
    await prefs.setString(_key, data);
  }

  Future<void> clearHosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
