import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthSession {
  final String token;
  final String email;
  AuthSession({required this.token, required this.email});
}

class AuthService {
  AuthService({required this.apiClient});

  final ApiClient apiClient;

  static const _tokenKey = 'auth_token';
  static const _emailKey = 'auth_email';

  Future<AuthSession?> currentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final email = prefs.getString(_emailKey);
    if (token != null && email != null) {
      return AuthSession(token: token, email: email);
    }
    return null;
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
  }

  Future<AuthSession> _persistSession(Map<String, dynamic> res) async {
    final token = res['token'] as String?;
    final user = res['user'] as Map<String, dynamic>?;
    if (token == null || user == null) {
      throw Exception('Invalid auth response');
    }
    final email = user['email'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
    return AuthSession(token: token, email: email);
  }
}
