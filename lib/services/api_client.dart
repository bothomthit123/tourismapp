import 'dart:convert';
import 'package:http/http.dart' as http;

/// API Client cho Tourism App
/// - Android emulator -> http://10.0.2.2:5000
/// - iOS simulator   -> http://localhost:5000
/// - Device thật      -> http://<IP máy dev>:5000
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ??
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:5022/api',
      ),
        _client = client ?? http.Client();
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = resp.body.isEmpty ? {} : jsonDecode(resp.body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return data as Map<String, dynamic>;
    throw Exception('POST $path -> ${resp.statusCode}: ${resp.body}');
  }
  // ------------------------------
  // Đăng ký tài khoản
  // ------------------------------
  Future<RegisterResult> register({
    required String name,
    required String email,
    required String password,
    String role = 'User',
  }) async {
    final uri = Uri.parse('$baseUrl/api/account/register');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
      }),
    );

    final body = resp.body.isEmpty ? {} : jsonDecode(resp.body);
    if (resp.statusCode == 201) {
      final data = body['data'] ?? {};
      return RegisterResult.ok(
        accountId: data['accountId'] ?? 0,
        email: data['email'] ?? email,
        role: data['role'] ?? role,
      );
    }

    final err =
    (body is Map && body['error'] is String) ? body['error'] as String : 'unknown_error';
    return RegisterResult.fail(err);
  }

  // ------------------------------
  // Đăng nhập
  // ------------------------------
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/account/login');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );

    final body = resp.body.isEmpty ? {} : jsonDecode(resp.body);
    if (resp.statusCode == 200) {
      final data = body['data'] ?? {};
      return LoginResult.ok(
        accountId: data['accountId'] ?? 0,
        email: data['email'] ?? email,
        role: data['role'] ?? 'User',
      );
    }

    final err =
    (body is Map && body['error'] is String) ? body['error'] as String : 'unknown_error';
    return LoginResult.fail(err);
  }
}

// ------------------------------
// Models cho kết quả API
// ------------------------------
class RegisterResult {
  final bool success;
  final int? accountId;
  final String? email;
  final String? role;
  final String? error;

  RegisterResult.ok({
    required this.accountId,
    required this.email,
    required this.role,
  })  : success = true,
        error = null;

  RegisterResult.fail(this.error)
      : success = false,
        accountId = null,
        email = null,
        role = null;
}

class LoginResult {
  final bool success;
  final int? accountId;
  final String? email;
  final String? role;
  final String? error;

  LoginResult.ok({
    required this.accountId,
    required this.email,
    required this.role,
  })  : success = true,
        error = null;

  LoginResult.fail(this.error)
      : success = false,
        accountId = null,
        email = null,
        role = null;
}
