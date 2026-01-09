import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';

class TripPage extends StatefulWidget {
  final String? authToken;
  const TripPage({super.key, this.authToken});

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  bool _loading = false;
  String? _error;
  List<Trip> _trips = [];

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.authToken ?? ""}',
  };

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await http.get(Uri.parse('$baseUrl/api/trips'), headers: _headers);
      if (!mounted) return; // [FIX] Kiểm tra mounted sau await

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final list = (json['data'] as List).map((e) => Trip.fromJson(e)).toList();
        setState(() => _trips = list);
      } else {
        setState(() => _error = "Lỗi ${resp.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Lỗi kết nối");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showTripDialog({Trip? trip}) async {
    final bool isEditing = trip != null;
    final result = await showDialog<Trip>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TripFormDialog(headers: _headers, trip: trip),
    );

    if (!mounted) return; // [FIX]

    if (result != null) {
      setState(() {
        if (isEditing) {
          final index = _trips.indexWhere((t) => t.tripId == result.tripId);
          if (index != -1) _trips[index] = result;
        } else {
          _trips.insert(0, result);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEditing ? "Đã cập nhật chuyến đi" : "Đã tạo chuyến đi mới"),
        backgroundColor: Colors.green,
      ));
    }
  }
  Future<void> _deleteTrip(int id) async {
    try {
      final resp = await http.delete(Uri.parse('$baseUrl/api/trips/$id'), headers: _headers);
      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        setState(() => _trips.removeWhere((t) => t.tripId == id));
      }
    } catch (e) { /* Ignore */ }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));

    if (_trips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.flight_takeoff, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Chưa có chuyến đi nào", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showTripDialog(),
              style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue),
              icon: const Icon(Icons.add),
              label: const Text("Tạo chuyến đi mới"),
            )
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadTrips,
          color: CrystalTheme.primaryBlue,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: _trips.length,
            separatorBuilder: (_,__) => const SizedBox(height: 16),
            itemBuilder: (context, index) => _buildTripCard(_trips[index]),
          ),
        ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton(
            onPressed: () => _showTripDialog(),
            backgroundColor: CrystalTheme.primaryBlue,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        )
      ],
    );
  }

  Widget _buildTripCard(Trip trip) {
    final dateRange = "${DateFormat('dd/MM').format(trip.startDate)} - ${DateFormat('dd/MM/yyyy').format(trip.endDate)}";
    return Dismissible(
      key: Key(trip.tripId.toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Xóa chuyến đi?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Hủy")),
            FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Xóa"))
          ],
        ),
      ),
      onDismissed: (_) => _deleteTrip(trip.tripId),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _showTripDialog(trip: trip),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
            image: DecorationImage(
              image: NetworkImage(trip.coverImageUrl ?? "https://picsum.photos/800/400"),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken),
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(trip.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(dateRange, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white54)),
                          child: Text("${trip.itemCount} hoạt động", style: const TextStyle(color: Colors.white, fontSize: 12)),
                        )
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(top: 12, right: 12, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 18))),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripFormDialog extends StatefulWidget {
  final Map<String, String> headers;
  final Trip? trip;
  const _TripFormDialog({required this.headers, this.trip});
  @override
  State<_TripFormDialog> createState() => _TripFormDialogState();
}

class _TripFormDialogState extends State<_TripFormDialog> {
  final _titleCtrl = TextEditingController();
  final _imgUrlCtrl = TextEditingController();

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 3));
  bool _saving = false;
  bool _uploading = false;
  final ImagePicker _picker = ImagePicker();
  File? _selectedImageFile;

  bool get _isEditing => widget.trip != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleCtrl.text = widget.trip!.title;
      _imgUrlCtrl.text = widget.trip!.coverImageUrl ?? "";
      _start = widget.trip!.startDate;
      _end = widget.trip!.endDate;
    }
  }

  Future<void> _pickAndUploadImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null) return;

    setState(() {
      _selectedImageFile = File(xfile.path);
      _uploading = true;
    });

    if (cloudinaryCloudName == 'YOUR_CLOUD_NAME') {
      if(mounted) { setState(() => _uploading = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chưa cấu hình Cloudinary!"))); }
      return;
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', xfile.path));

    try {
      final resp = await req.send();
      if (resp.statusCode == 200) {
        final str = await resp.stream.bytesToString();
        final url = jsonDecode(str)['secure_url'];
        if(mounted) setState(() => _imgUrlCtrl.text = url);
      }
    } catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload lỗi: $e"))); }
    finally { if(mounted) setState(() => _uploading = false); }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng nhập tên chuyến đi")));
      return;
    }

    setState(() => _saving = true);

    // [FIX TIMEZONE]
    // 1. Lấy phần ngày (Year, Month, Day)
    // 2. Cộng thêm 12h trưa để khi convert UTC không bị nhảy ngày
    final startUtc = DateTime(_start.year, _start.month, _start.day, 12).toUtc().toIso8601String();
    final endUtc = DateTime(_end.year, _end.month, _end.day, 12).toUtc().toIso8601String();

    final body = jsonEncode({
      "title": _titleCtrl.text,
      "startDate": startUtc,
      "endDate": endUtc,
      "coverImageUrl": _imgUrlCtrl.text.isNotEmpty ? _imgUrlCtrl.text : "https://picsum.photos/800/600"
    });

    try {
      http.Response resp;
      if (_isEditing) {
        resp = await http.put(Uri.parse('$baseUrl/api/trips/${widget.trip!.tripId}'), headers: widget.headers, body: body);
      } else {
        resp = await http.post(Uri.parse('$baseUrl/api/trips'), headers: widget.headers, body: body);
      }

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final data = (json['data'] is Map) ? json['data'] : json;
        if (mounted) Navigator.pop(context, Trip.fromJson(data));
      }
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e"))); }
    finally { if(mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(_isEditing ? "Sửa chuyến đi" : "Chuyến đi mới", style: TextStyle(color: CrystalTheme.textDark, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onTap: _uploading ? null : _pickAndUploadImage, child: Container(height: 150, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12), image: (_selectedImageFile != null) ? DecorationImage(image: FileImage(_selectedImageFile!), fit: BoxFit.cover) : (_imgUrlCtrl.text.isNotEmpty ? DecorationImage(image: NetworkImage(_imgUrlCtrl.text), fit: BoxFit.cover) : null)), alignment: Alignment.center, child: _uploading ? const CircularProgressIndicator() : (_imgUrlCtrl.text.isEmpty && _selectedImageFile == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_photo_alternate, color: Colors.grey, size: 32), SizedBox(height: 4), Text("Chọn ảnh bìa", style: TextStyle(color: Colors.grey))]) : null))),
          const SizedBox(height: 16),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Tên chuyến đi", filled: true)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2020), lastDate: DateTime(2030)); if(d!=null) setState(() => _start = d); }, child: Text("Từ: ${DateFormat('dd/MM').format(_start)}"))),
            Expanded(child: TextButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: _end, firstDate: DateTime(2020), lastDate: DateTime(2030)); if(d!=null) setState(() => _end = d); }, child: Text("Đến: ${DateFormat('dd/MM').format(_end)}"))),
          ])
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")), FilledButton(onPressed: (_saving || _uploading) ? null : _save, style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue), child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : Text(_isEditing ? "Lưu" : "Tạo"))],
    );
  }
}

class Trip {
  final int tripId; final String title; final DateTime startDate; final DateTime endDate; final String? coverImageUrl; final int itemCount;
  Trip({required this.tripId, required this.title, required this.startDate, required this.endDate, this.coverImageUrl, this.itemCount = 0});
  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      tripId: json['tripId'], title: json['title'],
      startDate: DateTime.parse(json['startDate']).toLocal(),
      endDate: DateTime.parse(json['endDate']).toLocal(),
      coverImageUrl: json['coverImageUrl'], itemCount: json['itemCount'] ?? 0,
    );
  }
}