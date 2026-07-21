import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  final fullNameController = TextEditingController();
  final otpController = TextEditingController(); // Controller cho OTP

  String _role = 'User';
  bool _loading = false;
  bool _isOtpSent = false; // Trạng thái: Đã gửi OTP chưa?

  // --- HÀM 1: GỬI MÃ OTP VỀ EMAIL ---
  Future<void> sendOtp() async {
    final email = emailController.text.trim().toLowerCase();
    final fullName = fullNameController.text.trim();
    final password = passwordController.text;

    // Validate cơ bản trước khi gửi OTP
    if (fullName.length < 2) {
      _toast("Họ và tên không hợp lệ");
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _toast("Email không hợp lệ");
      return;
    }
    if (password.length < 6) {
      _toast("Mật khẩu phải dài ít nhất 6 ký tự");
      return;
    }

    setState(() => _loading = true);
    final url = Uri.parse("$baseUrl/api/account/send-otp");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}), // Chỉ cần gửi email để nhận OTP
      );

      if (response.statusCode == 200) {
        _toast("Mã xác thực đã được gửi đến email của bạn! Kiểm tra mail spam nếu không thấy trong hộp thư đến");
        setState(() {
          _isOtpSent = true; // Chuyển sang giao diện nhập OTP
        });
      } else {
        final respBody = jsonDecode(response.body);
        _toast("Gửi mã thất bại: ${respBody['message'] ?? 'Lỗi server'}");
      }
    } catch (e) {
      _toast("Lỗi kết nối: $e");
      // [DEBUG MODE] Nếu chưa có API thật, mở comment dòng dưới để test giao diện
      // setState(() => _isOtpSent = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- HÀM 2: GỬI OTP + THÔNG TIN ĐỂ ĐĂNG KÝ ---
  Future<void> verifyAndRegister() async {
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;
    final fullName = fullNameController.text.trim();
    final otp = otpController.text.trim();

    if (otp.length < 4) { // Giả sử OTP 4 hoặc 6 số
      _toast("Vui lòng nhập mã xác thực hợp lệ");
      return;
    }

    setState(() => _loading = true);

    final url = Uri.parse("$baseUrl/api/account/register");
    final body = jsonEncode({
      "name": fullName,
      "email": email,
      "password": password,
      "role": _role,
      "otp": otp // Gửi kèm OTP để server verify
    });

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      final code = response.statusCode;
      final respBody = response.body.isEmpty ? {} : jsonDecode(response.body);

      if (code == 201 || code == 200) {
        _toast("Đăng ký & Xác thực thành công!");
        if (!mounted) return;
        Navigator.of(context).pop(); // Quay lại login
      } else {
        final err = (respBody is Map && respBody.containsKey('error'))
            ? respBody['error'].toString()
            : (respBody['message'] ?? 'Mã OTP không đúng hoặc hết hạn');
        _toast("Đăng ký thất bại: $err");
      }
    } catch (e) {
      _toast("Lỗi kết nối: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    passwordController.dispose();
    emailController.dispose();
    fullNameController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. BACKGROUND
          Positioned.fill(
            child: Image.asset(
              'assets/login.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF001020)),
            ),
          ),
          Container(color: const Color(0xFF001020).withOpacity(0.6)),

          // 2. NÚT BACK (Nếu đang nhập OTP thì back quay lại form điền thông tin)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(30),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (_isOtpSent) {
                    setState(() => _isOtpSent = false); // Quay lại bước 1
                  } else {
                    Navigator.of(context).pop(); // Thoát màn hình
                  }
                },
              ),
            ),
          ),

          // 3. NỘI DUNG FORM
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Text(
                    _isOtpSent ? "Xác thực Email" : "Đăng ký tài khoản",
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
                  if (_isOtpSent)
                    Text(
                      "Mã OTP đã được gửi đến:\n${emailController.text}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(height: 24),

                  // KHUNG KÍNH (GLASS CARD)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- TRẠNG THÁI 1: FORM ĐIỀN THÔNG TIN ---
                        if (!_isOtpSent) ...[
                          _buildTextField(
                              controller: fullNameController,
                              label: "Họ và tên",
                              icon: Icons.person_outline
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                              controller: emailController,
                              label: "Email",
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                              controller: passwordController,
                              label: "Mật khẩu",
                              icon: Icons.lock_outline,
                              obscureText: true
                          ),
                          const SizedBox(height: 16),
                          _buildRoleDropdown(),
                        ],

                        // --- TRẠNG THÁI 2: FORM NHẬP OTP ---
                        if (_isOtpSent) ...[
                          _buildTextField(
                            controller: otpController,
                            label: "Nhập mã xác thực (OTP)",
                            icon: Icons.security,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading ? null : sendOtp, // Gửi lại mã
                              child: Text("Gửi lại mã?", style: TextStyle(color: CrystalTheme.accentPink)),
                            ),
                          )
                        ],

                        const SizedBox(height: 24),

                        // NÚT HÀNH ĐỘNG
                        if (_loading)
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
                              // Nếu chưa gửi OTP -> Gọi hàm gửi OTP. Nếu rồi -> Gọi hàm verify
                              onPressed: _isOtpSent ? verifyAndRegister : sendOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                  _isOtpSent ? "Xác nhận & Đăng ký" : "Tiếp tục",
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                              ),
                            ),
                          ),

                        // LINK ĐĂNG NHẬP (Chỉ hiện ở bước 1)
                        if (!_isOtpSent) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Đã có tài khoản? ', style: TextStyle(color: Colors.white70)),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Text(
                                  'Đăng nhập',
                                  style: TextStyle(
                                    color: CrystalTheme.accentPink,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: CrystalTheme.accentPink,
                                  ),
                                ),
                              )
                            ],
                          )
                        ]
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

  // Các Widget con (TextField, Dropdown) giữ nguyên như cũ
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      cursorColor: CrystalTheme.primaryBlue,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: Colors.white.withOpacity(0.10),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white30),
          borderRadius: BorderRadius.circular(16),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: CrystalTheme.primaryBlue, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white30),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _role,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          dropdownColor: const Color(0xFF1A2935),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'User', child: Text('Người dùng (User)')),
            DropdownMenuItem(value: 'Supplier', child: Text('Nhà cung cấp (Supplier)')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'User'),
        ),
      ),
    );
  }
}