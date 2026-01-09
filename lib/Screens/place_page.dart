import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

// 1. Import Theme & Config
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';

// Import screens
import 'package:tourismapp/screens/advertisement_manager_page.dart';

class PlacePage extends StatefulWidget {
  final int accountId;
  final String? authToken;
  const PlacePage({super.key, required this.accountId, this.authToken});

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  bool _loading = true;
  String? _error;
  List<Place> _places = [];
  int? _supplierId;

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
    _loadProfileAndPlaces();
  }

  Future<void> _loadProfileAndPlaces() async {
    setState(() { _loading = true; _error = null; _places.clear(); });
    if (!_hasToken) {
      setState(() { _error = "Bạn cần đăng nhập với vai trò Supplier để quản lý."; _loading = false; });
      return;
    }

    try {
      final profileResponse = await http.get(Uri.parse('$baseUrl/me/profile'), headers: _authHeaders(json: false));
      if (!mounted) return;

      if (profileResponse.statusCode == 200) {
        final json = jsonDecode(profileResponse.body);
        final data = (json is Map && json['data'] is Map) ? json['data'] as Map : json;
        final supplierId = data['supplierId'];

        if (supplierId is int) {
          _supplierId = supplierId;
          await _loadMyPlaces();
        } else {
          throw Exception('Tài khoản này không phải là Supplier.');
        }
      } else {
        throw Exception('Lỗi tải profile: ${profileResponse.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = "Không thể xác thực tài khoản Supplier. (${e.toString()})"; _loading = false; });
    }
  }

  Future<void> _loadMyPlaces() async {
    if (_supplierId == null) return;

    // Debug: Kiểm tra xem Token có thực sự được gửi đi không (để fix lỗi 401)
    debugPrint("Đang tải Places cho SupplierId: $_supplierId");
    // debugPrint("Token đang dùng: ${widget.authToken}");

    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/suppliers/$_supplierId/places'),
          headers: _authHeaders(json: false) // Đảm bảo hàm này có gắn 'Authorization': 'Bearer ...'
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = (json is Map && json['data'] is List) ? json['data'] as List : [];

        setState(() {
          _places = data.map((item) => Place.fromJson(item))
          // [QUAN TRỌNG] Lọc lại lần nữa để đảm bảo chỉ hiện Place của chính mình
          // Nếu API trả nhầm Place của người khác, dòng này sẽ loại bỏ nó.
              .where((p) => p.supplierId == _supplierId)
              .toList();
        });
      } else if (response.statusCode == 401) {
        // Xử lý riêng lỗi 401 để biết đường login lại
        throw Exception('Hết phiên đăng nhập (401). Vui lòng đăng nhập lại.');
      } else {
        throw Exception('Lỗi API: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Lỗi _loadMyPlaces: $e"); // In lỗi ra console để debug
      if (!mounted) return;
      setState(() { _error = "Không thể tải danh sách (${e.toString()})"; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showPlaceFormDialog({Place? place}) async {
    // Security check (Code cũ đã thêm)
    if (place != null && place.supplierId != _supplierId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn không có quyền sửa địa điểm này!'), backgroundColor: Colors.red));
      return;
    }

    // Kiểm tra supplierId có null không trước khi mở form
    if (_supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa xác định được thông tin Supplier.'), backgroundColor: Colors.red));
      return;
    }

    final isEditing = place != null;
    final Place? result = await showDialog<Place>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PlaceFormDialog(
        place: place,
        baseUrl: baseUrl,
        authHeaders: _authHeaders(),
        supplierId: _supplierId!, // <--- TRUYỀN ID VÀO ĐÂY
      ),
    );
    if (result != null) {
      setState(() {
        if (isEditing) {
          final index = _places.indexWhere((p) => p.placeId == result.placeId);
          if (index != -1) _places[index] = result;
        } else {
          _places.insert(0, result);
        }
      });
    }
  }

  Future<void> _showDeleteConfirmation(Place place) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa địa điểm "${place.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Xóa')),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _deletePlace(place.placeId);
      if (success) {
        setState(() { _places.removeWhere((p) => p.placeId == place.placeId); });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Đã xóa địa điểm'), backgroundColor: CrystalTheme.primaryBlue));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xóa thất bại'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<bool> _deletePlace(int placeId) async {
    final url = Uri.parse('$baseUrl/api/places/$placeId');
    try {
      final response = await http.delete(url, headers: _authHeaders());
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) { return false; }
  }

  void _navigateToAdManager(Place place) {
    if (_supplierId == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => AdvertisementManagerPage(placeId: place.placeId, supplierId: _supplierId!, placeName: place.name, authToken: widget.authToken)));
  }

  Future<void> _showOptionsBottomSheet(Place place) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(padding: const EdgeInsets.all(16.0), child: Center(child: Text(place.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: CrystalTheme.textDark), overflow: TextOverflow.ellipsis))),
              const Divider(height: 1),
              ListTile(leading: Icon(Icons.edit, color: CrystalTheme.primaryBlue), title: const Text('Sửa thông tin'), onTap: () { Navigator.of(ctx).pop(); _showPlaceFormDialog(place: place); }),
              ListTile(leading: Icon(Icons.campaign, color: Colors.orange), title: const Text('Quản lý quảng cáo'), onTap: () { Navigator.of(ctx).pop(); _navigateToAdManager(place); }),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.delete, color: Colors.redAccent), title: const Text('Xóa địa điểm', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.of(ctx).pop(); _showDeleteConfirmation(place); }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [THEME] AppBar Gradient
      appBar: AppBar(
        title: const Text('Quản lý địa điểm', style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: CrystalTheme.blueGradient)),
        actions: [IconButton(onPressed: _loading ? null : _loadProfileAndPlaces, icon: const Icon(Icons.refresh))],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE1F5FE), Colors.white]),
        ),
        child: _buildBody(),
      ),
      floatingActionButton: _loading || _error != null ? null : FloatingActionButton.extended(
        onPressed: () => _showPlaceFormDialog(),
        backgroundColor: CrystalTheme.primaryBlue,
        icon: const Icon(Icons.add),
        label: const Text('Thêm mới'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center), const SizedBox(height: 12), if (_hasToken) FilledButton(onPressed: _loadProfileAndPlaces, style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue), child: const Text('Thử lại'))])));
    if (_places.isEmpty) return RefreshIndicator(onRefresh: _loadMyPlaces, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: MediaQuery.of(context).size.height / 4), const Center(child: Text('Bạn chưa có địa điểm nào.\nHãy nhấn nút (+) để thêm mới.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))]));

    return RefreshIndicator(
      color: CrystalTheme.primaryBlue,
      onRefresh: _loadMyPlaces,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemBuilder: (_, i) {
          final p = _places[i];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: CrystalTheme.lightBlueBg, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.storefront, color: CrystalTheme.primaryBlue)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(p.address ?? '(Chưa có địa chỉ)', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              trailing: IconButton(icon: const Icon(Icons.more_vert, color: Colors.grey), onPressed: () => _showOptionsBottomSheet(p)),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: _places.length,
      ),
    );
  }
}

// =======================================================================
// Dialog Form (Crystal Style)
// =======================================================================
class _PlaceFormDialog extends StatefulWidget {
  final Place? place;
  final String baseUrl;
  final Map<String, String> authHeaders;
  final int supplierId; // <--- THÊM DÒNG NÀY

  const _PlaceFormDialog({
    this.place,
    required this.baseUrl,
    required this.authHeaders,
    required this.supplierId, // <--- THÊM DÒNG NÀY
  });

  @override
  State<_PlaceFormDialog> createState() => _PlaceFormDialogState();
}

class _PlaceFormDialogState extends State<_PlaceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isGeocoding = false;

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;

  TimeOfDay? _openingTime;
  TimeOfDay? _closingTime;
  LatLng? _selectedCoords;
  bool get _isEditing => widget.place != null;

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    _nameController = TextEditingController(text: p?.name);
    _addressController = TextEditingController(text: p?.address);
    _descriptionController = TextEditingController(text: p?.description);
    _categoryController = TextEditingController(text: p?.category);
    if (p != null) _selectedCoords = LatLng(p.latitude, p.longitude);
    _openingTime = _parseTime(p?.openingHours);
    _closingTime = _parseTime(p?.closingHours);
  }

  TimeOfDay? _parseTime(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    try { final parts = timeString.split(':'); return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])); } catch (e) { return null; }
  }
  String _formatTime(TimeOfDay? time) => time == null ? 'Chưa chọn' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() { _nameController.dispose(); _addressController.dispose(); _descriptionController.dispose(); _categoryController.dispose(); super.dispose(); }

  Future<void> _reverseGeocode(LatLng coords) async {
    setState(() => _isGeocoding = true);
    try {
      final placemarks = await GeocodingPlatform.instance!.placemarkFromCoordinates(coords.latitude, coords.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _addressController.text = [p.street, p.subLocality, p.locality, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(', ');
      }
    } catch (e) { _showToast('Không tìm thấy địa chỉ', isError: true); } finally { if(mounted) setState(() => _isGeocoding = false); }
  }

  Future<void> _geocodeAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) { _showToast('Vui lòng nhập địa chỉ', isError: true); return; }
    setState(() => _isGeocoding = true);
    try {
      final locations = await GeocodingPlatform.instance!.locationFromAddress(address);
      if (locations.isNotEmpty) {
        setState(() => _selectedCoords = LatLng(locations.first.latitude, locations.first.longitude));
        _showToast('Đã tìm thấy vị trí!');
      } else { _showToast('Không tìm thấy vị trí', isError: true); }
    } catch (e) { _showToast('Lỗi: $e', isError: true); } finally { if (mounted) setState(() => _isGeocoding = false); }
  }

  Future<void> _pickOnMap() async {
    final LatLng? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => _MapPickerScreen(initialCoords: _selectedCoords)));
    if (result != null) { setState(() => _selectedCoords = result); await _reverseGeocode(result); }
  }

  Future<void> _pickTime(bool isOpeningTime) async {
    final newTime = await showTimePicker(context: context, initialTime: (isOpeningTime ? _openingTime : _closingTime) ?? TimeOfDay.now());
    if (newTime != null) setState(() { if (isOpeningTime) _openingTime = newTime; else _closingTime = newTime; });
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.redAccent : CrystalTheme.primaryBlue));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCoords == null) { _showToast('Vui lòng chọn tọa độ', isError: true); return; }
    setState(() => _isSaving = true);

    final data = {
      "name": _nameController.text.trim(),
      "address": _addressController.text.trim(),
      "description": _descriptionController.text.trim(),
      "category": _categoryController.text.trim(),
      "openingHours": _openingTime != null ? _formatTime(_openingTime) : null,
      "closingHours": _closingTime != null ? _formatTime(_closingTime) : null,
      "latitude": _selectedCoords!.latitude,
      "longitude": _selectedCoords!.longitude,

      // --- [FIX QUAN TRỌNG TẠI ĐÂY] ---
      // Nếu đang sửa thì giữ nguyên supplierId cũ, nếu thêm mới thì lấy từ tài khoản đang đăng nhập
      "supplierId": _isEditing ? widget.place!.supplierId : widget.supplierId,
    };

    final url = Uri.parse('${widget.baseUrl}/api/places${_isEditing ? '/${widget.place!.placeId}' : ''}');

    try {
      final response = _isEditing ? await http.put(url, headers: widget.authHeaders, body: jsonEncode(data)) : await http.post(url, headers: widget.authHeaders, body: jsonEncode(data));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final placeData = (json is Map && json.containsKey('data')) ? json['data'] : json;
        Navigator.of(context).pop(Place.fromJson(placeData));
      } else { _showToast('Lỗi: ${response.statusCode}', isError: true); }
    } catch (e) { _showToast('Lỗi kết nối: $e', isError: true); } finally { if (mounted) setState(() => _isSaving = false); }
  }

  // --- WIDGET HELPER: Tạo ô nhập liệu với tiêu đề nằm ngoài ---
  Widget _buildLabeledInput({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: CrystalTheme.textDark.withOpacity(0.8)
            )
        ),
        const SizedBox(height: 8), // Khoảng cách giữa tiêu đề và ô nhập
        child,
        const SizedBox(height: 16), // Khoảng cách giữa các field
      ],
    );
  }

  // Decoration chuẩn cho ô nhập (Không có labelText bên trong)
  InputDecoration get _inputDecoration => InputDecoration(
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: CrystalTheme.primaryBlue, width: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(_isEditing ? 'Sửa địa điểm' : 'Thêm mới', style: TextStyle(color: CrystalTheme.textDark, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabeledInput(
                  label: 'Tên địa điểm',
                  child: TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration.copyWith(hintText: 'Nhập tên...'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Bắt buộc' : null
                  ),
                ),

                _buildLabeledInput(
                  label: 'Địa chỉ',
                  child: TextFormField(
                    controller: _addressController,
                    decoration: _inputDecoration.copyWith(hintText: 'Nhập địa chỉ...'),
                  ),
                ),

                _buildLabeledInput(
                  label: 'Mô tả',
                  child: TextFormField(
                      controller: _descriptionController,
                      decoration: _inputDecoration.copyWith(hintText: 'Mô tả chi tiết...'),
                      maxLines: 3
                  ),
                ),

                _buildLabeledInput(
                  label: 'Danh mục',
                  child: TextFormField(
                    controller: _categoryController,
                    decoration: _inputDecoration.copyWith(hintText: 'Ví dụ: Nhà hàng, Cafe...'),
                  ),
                ),

                _buildLabeledInput(
                  label: 'Giờ hoạt động',
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey.shade50
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTime(_openingTime)),
                              const Icon(Icons.access_time, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text("-", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey.shade50
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatTime(_closingTime)),
                              const Icon(Icons.access_time, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),

                _buildLabeledInput(
                  label: 'Vị trí bản đồ',
                  child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedCoords == null ? 'Chưa chọn' : '${_selectedCoords!.latitude.toStringAsFixed(5)}, ${_selectedCoords!.longitude.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: 'Tìm địa chỉ',
                                onPressed: _isGeocoding ? null : _geocodeAddress
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(color: CrystalTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: IconButton(
                                  icon: Icon(Icons.map, color: CrystalTheme.primaryBlue),
                                  tooltip: 'Mở bản đồ',
                                  onPressed: _pickOnMap
                              ),
                            )
                          ]
                      )
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
        FilledButton(
            onPressed: _isSaving ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Lưu')
        ),
      ],
    );
  }
}

// [Giữ nguyên _MapPickerScreen và Place Model cũ]
class _MapPickerScreen extends StatefulWidget {
  final LatLng? initialCoords;
  const _MapPickerScreen({this.initialCoords});
  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}
class _MapPickerScreenState extends State<_MapPickerScreen> {
  late LatLng _currentCenter = widget.initialCoords ?? const LatLng(21.028511, 105.804817);
  final MapController _mapController = MapController();
  Future<void> _goToCurrentUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition();
      final newPos = LatLng(position.latitude, position.longitude);
      setState(() => _currentCenter = newPos);
      _mapController.move(newPos, 15.0);
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn vị trí')),
      body: Stack(children: [
        FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: _currentCenter, initialZoom: 15.0, onPositionChanged: (position, hasGesture) { if (hasGesture) _currentCenter = position.center ?? _currentCenter; }), children: [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.tourismapp')]),
        const Center(child: Icon(Icons.location_pin, color: Colors.red, size: 50)),
        Positioned(bottom: 80, right: 16, child: FloatingActionButton(heroTag: 'gps_button', onPressed: _goToCurrentUserLocation, child: const Icon(Icons.my_location))),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.of(context).pop(_currentCenter), label: const Text('Xác nhận'), icon: const Icon(Icons.check)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class Place {
  final int placeId;
  final String name;
  final String? address;
  final String? description;
  final double latitude;
  final double longitude;
  final String? category;
  final String? openingHours;
  final String? closingHours;
  final int? supplierId;
  final bool isPartnerPlace;

  Place({required this.placeId, required this.name, this.address, this.description, required this.latitude, required this.longitude, this.category, this.openingHours, this.closingHours, this.supplierId, this.isPartnerPlace = true});

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      placeId: json['placeId'] as int,
      name: json['name'] as String,
      address: json['address'] as String?,
      description: json['description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] as String?,
      openingHours: json['openingHours'] as String?,
      closingHours: json['closingHours'] as String?,
      supplierId: json['supplierId'] as int?,
      isPartnerPlace: json['isPartnerPlace'] as bool? ?? true,
    );
  }
}