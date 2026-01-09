import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Theme & Config
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';

class SecureDocsPage extends StatefulWidget {
  final String? authToken;
  const SecureDocsPage({super.key, this.authToken});

  @override
  State<SecureDocsPage> createState() => _SecureDocsPageState();
}

class _SecureDocsPageState extends State<SecureDocsPage> {
  // --- KHẮC PHỤC LỖI STORAGE ---
  // 1. Khởi tạo storage cố định, không dùng getter để tránh tạo lại instance liên tục
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // resetOnError: true giúp reset lại nếu key bị lỗi do cài lại app
      resetOnError: true,
    ),
  );

  final _pinController = TextEditingController();

  // State quản lý UI
  bool _isCheckingPin = true;
  bool _hasPin = false;
  bool _isLocked = true;

  bool _loading = false;
  bool _verifying = false;
  List<SecureDoc> _docs = [];

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.authToken ?? ""}',
  };

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  // --- LOGIC PIN ĐÃ SỬA ---

  // 1. Kiểm tra xem User đã từng tạo PIN chưa
  Future<void> _checkPinStatus() async {
    if (!mounted) return;
    setState(() => _isCheckingPin = true);

    try {
      // Đọc PIN từ bộ nhớ an toàn
      final pin = await _storage.read(key: 'vault_pin');
      debugPrint("KIỂM TRA PIN: ${pin == null ? 'Chưa có' : 'Đã có'}");

      if (!mounted) return;
      setState(() {
        _hasPin = (pin != null && pin.isNotEmpty);
        _isCheckingPin = false;
      });

      // Nếu đã có PIN nhưng chưa load danh sách (trường hợp hot reload), giữ khóa
    } catch (e) {
      debugPrint("LỖI ĐỌC PIN: $e");
      if (mounted) {
        setState(() {
          _hasPin = false; // Coi như chưa có để user tạo lại
          _isCheckingPin = false;
        });
      }
    }
  }

  // 2. Tạo PIN mới
  Future<void> _createPin(String pin) async {
    if (!mounted) return;
    setState(() => _verifying = true);

    await Future.delayed(const Duration(milliseconds: 300));

    try {
      debugPrint("Bắt đầu quy trình lưu PIN...");

      // BƯỚC A: Xóa key cũ trước (đề phòng key cũ bị corrupt)
      try {
        await _storage.delete(key: 'vault_pin');
      } catch (_) {} // Bỏ qua lỗi nếu chưa có key

      // BƯỚC B: Ghi key mới
      await _storage.write(key: 'vault_pin', value: pin);

      // BƯỚC C: Kiểm tra lại (Verify)
      String? verifyRead = await _storage.read(key: 'vault_pin');

      // Nếu đọc lại mà vẫn null, nghĩa là bộ nhớ bị kẹt -> Cần Reset toàn bộ
      if (verifyRead == null) {
        debugPrint("Ghi thất bại lần 1, tiến hành Reset Storage...");
        await _storage.deleteAll(); // Xóa sạch sành sanh tất cả
        await _storage.write(key: 'vault_pin', value: pin); // Ghi lại lần 2
        verifyRead = await _storage.read(key: 'vault_pin'); // Check lại lần 2
      }

      if (verifyRead != pin) {
        throw Exception("Không thể ghi vào bộ nhớ máy (Storage Error)");
      }

      if (!mounted) return;
      setState(() {
        _hasPin = true;
        _isLocked = false;
        _verifying = false;
        _pinController.clear();
      });

      _loadDocs();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã lưu mã PIN an toàn"), backgroundColor: Colors.green)
      );

    } catch (e) {
      debugPrint("LỖI NGHIÊM TRỌNG: $e");
      if (mounted) {
        setState(() => _verifying = false);
        // Hiển thị lỗi chi tiết để debug
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lỗi bộ nhớ máy. Vui lòng gỡ app và cài lại."), backgroundColor: Colors.red)
        );
      }
    }
  }

  // 3. Mở khóa
  Future<void> _unlock(String inputPin) async {
    if (!mounted) return;
    setState(() => _verifying = true);

    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final savedPin = await _storage.read(key: 'vault_pin');

      if (!mounted) return;
      setState(() => _verifying = false);

      if (savedPin == inputPin) {
        setState(() {
          _isLocked = false;
          _pinController.clear();
        });
        _loadDocs();
      } else {
        _pinController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Mã PIN không đúng"), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (mounted) setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi hệ thống bảo mật"), backgroundColor: Colors.red)
      );
    }
  }

  // --- CÁC HÀM API ---
  Future<void> _loadDocs() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse('$baseUrl/api/securedocument'), headers: _headers);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        // Kiểm tra cấu trúc JSON trả về có đúng không
        if (json['data'] != null) {
          final list = (json['data'] as List).map((e) => SecureDoc.fromJson(e)).toList();
          if (mounted) setState(() => _docs = list);
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải docs: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteDoc(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xóa giấy tờ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Xóa")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await http.delete(Uri.parse('$baseUrl/api/securedocument/$id'), headers: _headers);
        if (mounted) {
          setState(() => _docs.removeWhere((d) => d.docId == id));
        }
      } catch (e) {
        debugPrint("Lỗi xóa: $e");
      }
    }
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddDocDialog(headers: _headers),
    );

    if (result == true) {
      _loadDocs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã lưu giấy tờ!"), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trạng thái đang khởi động/kiểm tra
    if (_isCheckingPin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLocked ? "Bảo Mật" : "Két Sắt Của Tôi"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (!_isLocked && _hasPin)
            IconButton(
              icon: const Icon(Icons.lock_outline),
              onPressed: () {
                setState(() {
                  _isLocked = true;
                  _docs = []; // Xóa data khỏi RAM khi khóa lại
                });
              },
              tooltip: "Khóa lại",
            )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 1. Chưa có PIN -> Hiện màn hình Tạo mới
    if (!_hasPin) {
      return _buildPinSetupScreen(
        title: "Thiết lập mã PIN mới",
        subtitle: "Tạo mã PIN 4 số để bảo vệ giấy tờ quan trọng của bạn",
        buttonText: "Lưu mã PIN",
        onSubmit: (pin) => _createPin(pin),
      );
    }

    // 2. Có PIN nhưng chưa mở -> Hiện màn hình Nhập mã
    if (_isLocked) {
      return _buildPinSetupScreen(
        title: "Nhập mã PIN",
        subtitle: "Nhập mã PIN để mở khóa két sắt",
        buttonText: "Mở khóa",
        onSubmit: (pin) => _unlock(pin),
        isUnlock: true,
      );
    }

    // 3. Đã mở khóa -> Hiện nội dung
    if (_loading) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));

    if (_docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text("Chưa có giấy tờ nào", style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddDialog,
              style: FilledButton.styleFrom(
                  backgroundColor: CrystalTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
              ),
              icon: const Icon(Icons.add),
              label: const Text("Thêm giấy tờ ngay"),
            )
          ],
        ),
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.75
          ),
          itemCount: _docs.length,
          itemBuilder: (context, index) => _buildDocCard(_docs[index]),
        ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            onPressed: _showAddDialog,
            backgroundColor: CrystalTheme.primaryBlue,
            icon: const Icon(Icons.add_a_photo, color: Colors.white),
            label: const Text("Thêm", style: TextStyle(color: Colors.white)),
          ),
        )
      ],
    );
  }

  Widget _buildDocCard(SecureDoc doc) {
    return GestureDetector(
      onTap: () {
        // Có thể thêm tính năng xem ảnh phóng to ở đây
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
          border: Border.all(color: doc.isPinned ? Colors.orange : Colors.transparent, width: doc.isPinned ? 2 : 0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    doc.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_,__,___) => const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title, style: TextStyle(fontWeight: FontWeight.w600, color: CrystalTheme.textDark, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: CrystalTheme.lightBlueBg, borderRadius: BorderRadius.circular(6)),
                        child: Text(doc.docType, style: TextStyle(fontSize: 11, color: CrystalTheme.primaryBlueDark, fontWeight: FontWeight.bold)),
                      ),
                      GestureDetector(
                        onTap: () => _deleteDoc(doc.docId),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.1)),
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI NHẬP PIN ---
  Widget _buildPinSetupScreen({
    required String title,
    String? subtitle,
    required String buttonText,
    required Function(String) onSubmit,
    bool isUnlock = false
  }) {
    return SingleChildScrollView( // Thêm ScrollView để tránh lỗi tràn màn hình khi bàn phím hiện
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: CrystalTheme.primaryBlue.withOpacity(0.1),
                    shape: BoxShape.circle
                ),
                child: Icon(isUnlock ? Icons.lock_open_rounded : Icons.shield_rounded, size: 60, color: CrystalTheme.primaryBlue),
              ),
              const SizedBox(height: 24),
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: CrystalTheme.textDark), textAlign: TextAlign.center),
              if(subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),

              // Ô nhập PIN
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "••••",
                    hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 16),
                    border: InputBorder.none,
                    counterText: "",
                    filled: false,
                  ),
                  onChanged: (val) {
                    if (val.length == 4 && !_verifying) {
                      onSubmit(val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 40),

              if (_verifying)
                const CircularProgressIndicator(color: CrystalTheme.primaryBlue)
              else
                FilledButton(
                  onPressed: () {
                    if (_pinController.text.length == 4) {
                      onSubmit(_pinController.text);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng nhập đủ 4 số")));
                    }
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: CrystalTheme.primaryBlue,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  ),
                  child: Text(buttonText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                )
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================
// DIALOG THÊM GIẤY TỜ (GIỮ NGUYÊN LOGIC, CHỈ SỬA UI)
// ==================================================
class _AddDocDialog extends StatefulWidget {
  final Map<String, String> headers;
  const _AddDocDialog({required this.headers});
  @override
  State<_AddDocDialog> createState() => _AddDocDialogState();
}

class _AddDocDialogState extends State<_AddDocDialog> {
  final _titleCtrl = TextEditingController();
  String _docType = "Passport";
  File? _imageFile;
  bool _isUploading = false;
  bool _isPinned = false;
  final ImagePicker _picker = ImagePicker();

  // --- LOGIC UPLOAD ẢNH (Sử dụng Cloudinary) ---
  // Lưu ý: Bạn cần điền đúng cloud_name và upload_preset của bạn vào Conts/api_config.dart hoặc điền trực tiếp vào đây
  Future<String?> _uploadImage(File file) async {
    // TODO: Thay thế bằng cloudname thực tế của bạn nếu chưa có trong config
    const String cloudName = cloudinaryCloudName;
    const String uploadPreset = cloudinaryUploadPreset;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    try {
      final resp = await req.send();
      if (resp.statusCode == 200) {
        final str = await resp.stream.bytesToString();
        return jsonDecode(str)['secure_url'];
      } else {
        debugPrint("Upload failed: ${resp.statusCode}");
      }
    } catch (e) {
      debugPrint("Upload error: $e");
    }
    return null;
  }

  Future<void> _pickImage(ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 80);
    if (xfile != null) setState(() => _imageFile = File(xfile.path));
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty || _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng nhập tên và chọn ảnh")));
      return;
    }
    setState(() => _isUploading = true);

    final imageUrl = await _uploadImage(_imageFile!);
    if (imageUrl == null) {
      if(mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi upload ảnh lên Cloudinary"), backgroundColor: Colors.red));
      }
      return;
    }

    final body = jsonEncode({
      "title": _titleCtrl.text,
      "docType": _docType,
      "imageUrl": imageUrl,
      "isPinned": _isPinned
    });

    try {
      final resp = await http.post(Uri.parse('$baseUrl/api/securedocument'), headers: widget.headers, body: body);
      if (resp.statusCode == 201 && mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("API Error: $e");
    } finally {
      if(mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text("Thêm giấy tờ"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Tên giấy tờ", filled: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _docType,
              decoration: const InputDecoration(labelText: "Loại", filled: true),
              items: ["Passport", "Visa", "CCCD", "Bảo hiểm", "Vé máy bay", "Khác"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _docType = v!),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _pickImage(ImageSource.gallery),
              child: Container(
                height: 150, width: double.infinity,
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null,
                    border: Border.all(color: Colors.grey.shade300)
                ),
                child: _imageFile == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.camera_alt, color: Colors.grey, size: 40), Text("Chọn ảnh từ thư viện", style: TextStyle(color: Colors.grey))]) : null,
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text("Ghim quan trọng"),
              value: _isPinned,
              onChanged: (v) => setState(() => _isPinned = v!),
              activeColor: CrystalTheme.primaryBlue,
              contentPadding: EdgeInsets.zero,
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
        FilledButton(
          onPressed: _isUploading ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue),
          child: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Lưu"),
        )
      ],
    );
  }
}

// --- MODEL ---
class SecureDoc {
  final int docId;
  final String title;
  final String docType;
  final String imageUrl;
  final bool isPinned;
  SecureDoc({required this.docId, required this.title, required this.docType, required this.imageUrl, required this.isPinned});
  factory SecureDoc.fromJson(Map<String, dynamic> json) {
    return SecureDoc(
      docId: json['docId'] ?? 0,
      title: json['title'] ?? "Không tên",
      docType: json['docType'] ?? "Khác",
      imageUrl: json['imageUrl'] ?? "",
      isPinned: json['isPinned'] ?? false,
    );
  }
}