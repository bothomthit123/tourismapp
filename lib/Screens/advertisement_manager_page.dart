import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

// 1. Import Theme & Config
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';

class AdvertisementManagerPage extends StatefulWidget {
  final int placeId;
  final int supplierId;
  final String placeName;
  final String? authToken;

  const AdvertisementManagerPage({
    super.key,
    required this.placeId,
    required this.supplierId,
    required this.placeName,
    this.authToken,
  });

  @override
  State<AdvertisementManagerPage> createState() => _AdvertisementManagerPageState();
}

class _AdvertisementManagerPageState extends State<AdvertisementManagerPage> {
  bool _loading = true;
  String? _error;
  List<Advertisement> _advertisements = [];

  bool get _hasToken => (widget.authToken ?? '').isNotEmpty;

  Map<String, String> _authHeaders({bool json = true}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    h['Accept'] = 'application/json';
    if (_hasToken) h['Authorization'] = 'Bearer ${widget.authToken}';
    return h;
  }

  @override
  void initState() {
    super.initState();
    _loadAdvertisements();
  }

  Future<void> _loadAdvertisements() async {
    setState(() { _loading = true; _error = null; });
    try {
      final url = Uri.parse('$baseUrl/api/advertisements/for-place/${widget.placeId}');
      final response = await http.get(url, headers: _authHeaders(json: false));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = (json is Map && json['data'] is List) ? json['data'] as List : [];
        setState(() {
          _advertisements = data.map((item) => Advertisement.fromJson(item)).toList();
        });
      } else {
        throw Exception('Lỗi ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Không thể tải danh sách quảng cáo. Vui lòng thử lại.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAdFormDialog({Advertisement? ad}) async {
    final bool isEditing = ad != null;

    final Advertisement? result = await showDialog<Advertisement>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _AdFormDialog(
          advertisement: ad,
          placeId: widget.placeId,
          supplierId: widget.supplierId,
          baseUrl: baseUrl,
          authHeaders: _authHeaders(),
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isEditing) {
          final index = _advertisements.indexWhere((a) => a.adId == result.adId);
          if (index != -1) _advertisements[index] = result;
        } else {
          _advertisements.insert(0, result);
        }
      });
    }
  }

  Future<void> _showDeleteConfirmation(Advertisement ad) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa quảng cáo "${ad.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Xóa')),
        ],
      ),
    );

    if (confirmed == true) {
      final url = Uri.parse('$baseUrl/api/advertisements/${ad.adId}');
      try {
        final response = await http.delete(url, headers: _authHeaders());
        if (response.statusCode == 200 || response.statusCode == 204) {
          setState(() {
            _advertisements.removeWhere((a) => a.adId == ad.adId);
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Đã xóa quảng cáo'), backgroundColor: CrystalTheme.primaryBlue));
        } else {
          throw Exception('Lỗi ${response.statusCode}');
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xóa thất bại: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [THEME] AppBar Gradient
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quản lý quảng cáo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            Text(widget.placeName, style: const TextStyle(fontSize: 14, color: Colors.white70)),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: CrystalTheme.blueGradient,
          ),
        ),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFFE1F5FE), Colors.white],
            )
        ),
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAdFormDialog(),
        backgroundColor: CrystalTheme.primaryBlue,
        icon: const Icon(Icons.add),
        label: const Text('Tạo mới'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadAdvertisements, style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue), child: const Text('Thử lại')),
          ]),
        ),
      );
    }

    if (_advertisements.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAdvertisements,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height / 4),
            const Center(child: Text('Chưa có quảng cáo nào.\nNhấn nút (+) để tạo mới.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: CrystalTheme.primaryBlue,
      onRefresh: _loadAdvertisements,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _advertisements.length,
        itemBuilder: (context, index) {
          final ad = _advertisements[index];
          final bool isActive = ad.isActive();

          // [THEME] Card Style
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
              border: isActive ? Border.all(color: CrystalTheme.primaryBlue.withOpacity(0.3)) : null,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ad.bannerImageUrl != null && ad.bannerImageUrl!.isNotEmpty
                    ? Image.network(ad.bannerImageUrl!, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: 60, height: 60, color: Colors.grey.shade200, child: const Icon(Icons.broken_image, color: Colors.grey)))
                    : Container(width: 60, height: 60, color: CrystalTheme.lightBlueBg, child: Icon(Icons.campaign, color: CrystalTheme.primaryBlue)),
              ),
              title: Text(ad.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('${ad.formatDate(ad.startUtc)} - ${ad.formatDate(ad.endUtc)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(isActive ? "Đang chạy" : "Đã dừng", style: TextStyle(color: isActive ? Colors.green : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              trailing: PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 20, color: Colors.blue), SizedBox(width: 8), Text('Sửa')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Xóa')])),
                ],
                onSelected: (val) {
                  if (val == 'edit') _showAdFormDialog(ad: ad);
                  if (val == 'delete') _showDeleteConfirmation(ad);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// =======================================================================
// Dialog Form (Crystal Style)
// =======================================================================
class _AdFormDialog extends StatefulWidget {
  final Advertisement? advertisement;
  final int placeId;
  final int supplierId;
  final String baseUrl;
  final Map<String, String> authHeaders;

  const _AdFormDialog({
    this.advertisement,
    required this.placeId,
    required this.supplierId,
    required this.baseUrl,
    required this.authHeaders,
  });

  @override
  State<_AdFormDialog> createState() => _AdFormDialogState();
}

class _AdFormDialogState extends State<_AdFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;

  DateTime? _startDate;
  DateTime? _endDate;

  final ImagePicker _picker = ImagePicker();
  File? _selectedImageFile;
  bool _isUploading = false;

  bool get _isEditing => widget.advertisement != null;

  @override
  void initState() {
    super.initState();
    final ad = widget.advertisement;
    _titleController = TextEditingController(text: ad?.title);
    _descriptionController = TextEditingController(text: ad?.description);
    _imageUrlController = TextEditingController(text: ad?.bannerImageUrl);
    _startDate = ad?.startUtc;
    _endDate = ad?.endUtc;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  // [Cloudinary Logic giữ nguyên]
  Future<String?> _uploadImageToCloudinary(File imageFile) async {
    if (cloudinaryCloudName == 'YOUR_CLOUD_NAME') {
      _showToast('Vui lòng cấu hình Cloudinary', isError: true);
      return null;
    }
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    setState(() => _isUploading = true);
    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        return json.decode(resStr)['secure_url'];
      } else {
        _showToast('Upload thất bại', isError: true);
        return null;
      }
    } catch (e) {
      _showToast('Lỗi: $e', isError: true);
      return null;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;

    final File imageFile = File(image.path);
    setState(() => _selectedImageFile = imageFile);

    final String? secureUrl = await _uploadImageToCloudinary(imageFile);
    if (secureUrl != null && mounted) {
      setState(() => _imageUrlController.text = secureUrl);
      _showToast('Tải ảnh thành công!');
    } else {
      setState(() => _selectedImageFile = null);
    }
  }

  Future<void> _pickDate(bool isStartDate) async {
    final now = DateTime.now();
    final initialDate = (isStartDate ? _startDate : _endDate) ?? now;
    final DateTime? newDate = await showDatePicker(
      context: context, initialDate: initialDate, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: CrystalTheme.primaryBlue)), child: child!);
      },
    );

    if (newDate != null) {
      setState(() {
        if (isStartDate) {
          _startDate = newDate;
          if (_endDate == null || _endDate!.isBefore(newDate)) _endDate = newDate.add(const Duration(days: 7));
        } else {
          _endDate = newDate;
          if (_startDate != null && newDate.isBefore(_startDate!)) _startDate = newDate;
        }
      });
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.redAccent : CrystalTheme.primaryBlue));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) { _showToast('Vui lòng chọn thời gian', isError: true); return; }

    setState(() => _isSaving = true);
    final data = {
      "placeId": widget.placeId, "supplierId": widget.supplierId, "title": _titleController.text.trim(), "description": _descriptionController.text.trim(),
      "bannerImageUrl": _imageUrlController.text.trim(), "startUtc": _startDate!.toUtc().toIso8601String(), "endUtc": _endDate!.toUtc().toIso8601String(),
    };
    final url = Uri.parse('${widget.baseUrl}/api/advertisements${_isEditing ? '/${widget.advertisement!.adId}' : ''}');

    try {
      final response = _isEditing ? await http.put(url, headers: widget.authHeaders, body: jsonEncode(data)) : await http.post(url, headers: widget.authHeaders, body: jsonEncode(data));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        Navigator.of(context).pop(Advertisement.fromJson((json is Map && json['data'] is Map) ? json['data'] : json));
      } else {
        _showToast('Lỗi: ${response.statusCode}', isError: true);
      }
    } catch (e) { _showToast('Lỗi kết nối: $e', isError: true); }
    finally { if (mounted) setState(() => _isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    // Custom Input Decoration
    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      filled: true, fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: CrystalTheme.primaryBlue)),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(_isEditing ? 'Sửa quảng cáo' : 'Tạo mới', style: TextStyle(color: CrystalTheme.textDark, fontWeight: FontWeight.bold)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(controller: _titleController, decoration: decoration('Tiêu đề'), validator: (v) => (v?.isEmpty ?? true) ? 'Bắt buộc' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _descriptionController, decoration: decoration('Mô tả ngắn'), maxLines: 2),
            const SizedBox(height: 16),

            // Image Picker
            GestureDetector(
              onTap: _isSaving ? null : _pickImage,
              child: Container(
                height: 140, width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid)),
                child: _isUploading
                    ? const Center(child: CircularProgressIndicator())
                    : (_selectedImageFile != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_selectedImageFile!, fit: BoxFit.cover))
                    : (_imageUrlController.text.isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_imageUrlController.text, fit: BoxFit.cover))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey), Text("Chọn ảnh banner", style: TextStyle(color: Colors.grey))]))),
              ),
            ),

            const SizedBox(height: 16),
            // Date Pickers
            Row(children: [
              Expanded(child: InkWell(onTap: () => _pickDate(true), child: InputDecorator(decoration: decoration('Bắt đầu'), child: Text(_startDate == null ? '-' : DateFormat('dd/MM').format(_startDate!))))),
              const SizedBox(width: 12),
              Expanded(child: InkWell(onTap: () => _pickDate(false), child: InputDecorator(decoration: decoration('Kết thúc'), child: Text(_endDate == null ? '-' : DateFormat('dd/MM').format(_endDate!))))),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
        FilledButton(onPressed: _isSaving ? null : _submit, style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Lưu')),
      ],
    );
  }
}

class Advertisement {
  final int adId;
  final int placeId;
  final int supplierId;
  final String title;
  final String? description;
  final String? bannerImageUrl;
  final DateTime startUtc;
  final DateTime endUtc;

  Advertisement({required this.adId, required this.placeId, required this.supplierId, required this.title, this.description, this.bannerImageUrl, required this.startUtc, required this.endUtc});

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    return Advertisement(
      adId: json['adId'] as int,
      placeId: json['placeId'] as int,
      supplierId: json['supplierId'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      bannerImageUrl: json['bannerImageUrl'] as String?,
      startUtc: DateTime.parse(json['startUtc'] as String),
      endUtc: DateTime.parse(json['endUtc'] as String),
    );
  }

  bool isActive() { final now = DateTime.now().toUtc(); return now.isAfter(startUtc) && now.isBefore(endUtc); }
  String formatDate(DateTime date) { return DateFormat('dd/MM/yyyy').format(date.toLocal()); }
}