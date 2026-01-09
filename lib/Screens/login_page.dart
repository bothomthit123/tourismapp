import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';
import 'main_navigation.dart';
import 'package:tourismapp/screens/register_page.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  String? _errorMessage;

  void _togglePasswordVisibility() => setState(() => _obscureText = !_obscureText);

  // Cấu hình fix lỗi KeyStore trên Android
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );

  String? _pickToken(Map obj, Map<String, String> headers) {
    String? t;
    if (obj['data'] is Map) t = (obj['data']['token'] ?? obj['data']['jwt'] ?? obj['data']['access_token'])?.toString();
    t ??= (obj['token'] ?? obj['jwt'] ?? obj['access_token'])?.toString();
    t ??= headers['authorization'];
    if (t != null && t.toLowerCase().startsWith('bearer ')) t = t.substring(7).trim();
    return (t != null && t.isNotEmpty) ? t : null;
  }

  int _pickAccountId(Map obj) {
    if (obj['data'] is Map && (obj['data']['accountId'] is int)) return obj['data']['accountId'] as int;
    if (obj['accountId'] is int) return obj['accountId'] as int;
    return 0;
  }

  Future<void> _login() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    final url = Uri.parse("$baseUrl/api/account/login");
    final body = jsonEncode({
      "email": _emailController.text.trim().toLowerCase(),
      "password": _passwordController.text,
    });

    try {
      final resp = await http.post(url, headers: {"Content-Type": "application/json"}, body: body);

      if (resp.statusCode == 200) {
        final obj = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(resp.bodyBytes)) as Map;
        final token = _pickToken(obj, resp.headers);
        final accountId = _pickAccountId(obj);

        if (token != null && accountId != 0) {
          try {
            final storage = FlutterSecureStorage(aOptions: _getAndroidOptions());
            await storage.write(key: 'auth_token', value: token);
            await storage.write(key: 'account_id', value: accountId.toString());
          } catch (storageError) {
            debugPrint(">>>> LỖI STORAGE: $storageError");
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => MainNavigation(accountId: accountId, authToken: token)),
          );
        } else {
          setState(() { _errorMessage = "Đăng nhập thất bại: Token không hợp lệ."; _isLoading = false; });
        }
      } else if (resp.statusCode == 401) {
        setState(() { _errorMessage = 'Email hoặc mật khẩu không đúng.'; _isLoading = false; });
      } else {
        setState(() { _errorMessage = "Tài khoản bị khóa (${resp.statusCode})."; _isLoading = false; });
      }
    } catch (e) {
      debugPrint(">>>> LỖI KẾT NỐI: $e");
      setState(() { _errorMessage = "Không thể kết nối đến máy chủ."; _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. Nền ảnh
          Positioned.fill(
            child: Image.asset('assets/login.png', fit: BoxFit.cover, filterQuality: FilterQuality.low),
          ),
          // 2. Lớp phủ đen mờ
          Container(color: const Color(0xFF001020).withOpacity(0.6)),

          // 3. Nội dung chính
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/travel_logo.png', height: 100),
                  const SizedBox(height: 16),
                  Text(
                    'Smart Travel',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(offset: const Offset(0, 2), blurRadius: 10, color: CrystalTheme.primaryBlue.withOpacity(0.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Khám phá thế giới theo cách của bạn',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 32),

                  // --- KHUNG LOGIN ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))
                      ],
                    ),
                    child: Column(
                      children: [
                        // EMAIL INPUT
                        TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          cursorColor: CrystalTheme.primaryBlue,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                            labelText: 'Email',
                            labelStyle: const TextStyle(color: Colors.white70),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                            filled: true,
                            fillColor: Colors.black12,
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.white30),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              // Dùng CrystalTheme.primaryBlue
                              borderSide: BorderSide(color: CrystalTheme.primaryBlue, width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // PASSWORD INPUT
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscureText,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          cursorColor: CrystalTheme.primaryBlue,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                            labelText: 'Mật khẩu',
                            labelStyle: const TextStyle(color: Colors.white70),
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                            filled: true,
                            fillColor: Colors.black12,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: Colors.white70,
                              ),
                              onPressed: _togglePasswordVisibility,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.white30),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            focusedBorder: OutlineInputBorder(
                              // [SỬA] Dùng CrystalTheme.primaryBlue
                              borderSide: BorderSide(color: CrystalTheme.primaryBlue, width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),

                        // BUTTON ĐĂNG NHẬP
                        if (_isLoading)
                          const CircularProgressIndicator(color: CrystalTheme.primaryBlue)
                        else
                          Container(
                            width: double.infinity,
                            height: 50,
                            decoration: BoxDecoration(
                                gradient: CrystalTheme.blueGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                                ]
                            ),
                            child: ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text(
                                  'Đăng nhập',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        // LINK ĐĂNG KÝ
                        TextButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                          child: RichText(
                            text: TextSpan(
                              text: 'Chưa có tài khoản? ',
                              style: const TextStyle(color: Colors.white70),
                              children: [
                                TextSpan(
                                  text: 'Đăng ký ngay',
                                  style: TextStyle(
                                    // [SỬA] Dùng CrystalTheme.accentPink
                                    color: CrystalTheme.accentPink,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: CrystalTheme.accentPink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}