import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tourismapp/Conts/api_config.dart';
import 'package:tourismapp/main.dart';
import 'package:tourismapp/Models/download_config_provider.dart';
import 'package:tourismapp/screens/offline_maps_page.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'dart:io';

// =======================================================
// 1. MODELS & CLIENTS
// =======================================================

class _FoursquareClient {
  static const String _endpoint = 'https://places-api.foursquare.com/places/search';
  final String apiKey;
  final String apiVersion;
  const _FoursquareClient({required this.apiKey, this.apiVersion = '2025-06-17'});

  Future<Map<String, dynamic>> search({
    required String query,
    required LatLng center,
    int limit = 15,
    int radius = 1500,
    String sort = 'RELEVANCE',
    String? categories,
  }) async {
    var url = '$_endpoint'
        '?query=${Uri.encodeComponent(query)}'
        '&ll=${center.latitude},${center.longitude}'
        '&limit=$limit'
        '&radius=$radius'
        '&sort=${sort.toUpperCase()}';

    if (categories != null && categories.isNotEmpty) {
      url += '&categories=$categories';
    }

    final uri = Uri.parse(url);
    final headers = {
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Accept': 'application/json',
      'X-Places-Api-Version': apiVersion,
    };
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      debugPrint('[FSQ] Error: ${resp.statusCode} ${resp.body}');
      throw Exception('FSQ ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

class MapPlace {
  final String providerId;
  final String name;
  final String address;
  final String category;
  final double lat;
  final double lng;
  final int? supplierId;

  const MapPlace({
    required this.providerId,
    required this.name,
    required this.address,
    required this.category,
    required this.lat,
    required this.lng,
    this.supplierId,
  });


  Map<String, dynamic> toJson() {
    String provider;
    String id;

    if (providerId.startsWith('osm_')) {
      provider = 'osm';
      id = providerId.substring(4);
    } else if (providerId.startsWith('fsq_')) {
      provider = 'foursquare';
      id = providerId.substring(4);
    } else if (providerId.startsWith('internal_')) {
      provider = 'internal';
      id = providerId.substring(9); // Cắt bỏ chữ 'internal_' (9 ký tự)
    } else {
      provider = 'unknown';
      id = providerId;
    }

    return {
      'provider': provider,
      'providerId': id,
      'name': name,
      'address': address,
      'category': category,
      'latitude': lat,
      'longitude': lng,
      'supplierId': supplierId,
    };
  }
}

enum SearchProvider { foursquare, osm }

class Advertisement {
  final int adId;
  final int placeId;
  final int? supplierId;
  final String title;
  final String? description;
  final String? bannerImageUrl;
  final DateTime? startUtc;
  final DateTime? endUtc;
  final double? latitude;
  final double? longitude;
  // 2 trường để hiển thị địa chỉ rõ ràng hơn
  final String? placeName;
  final String? placeAddress;

  Advertisement({
    required this.adId,
    required this.placeId,
    this.supplierId,
    required this.title,
    this.description,
    this.bannerImageUrl,
    this.startUtc,
    this.endUtc,
    this.latitude,
    this.longitude,
    this.placeName,
    this.placeAddress,
  });

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    return Advertisement(
      // Dùng toán tử ?? 0 để tránh crash nếu API không trả về adId
      adId: json['adId'] != null ? json['adId'] as int : 0,

      placeId: json['placeId'] != null ? json['placeId'] as int : 0,
      supplierId: json['supplierId'] as int?,
      title: json['title'] as String? ?? "Không có tiêu đề", // Safety check
      description: json['description'] as String?,
      bannerImageUrl: json['bannerImageUrl'] as String?,

      // Parse ngày tháng an toàn hơn
      startUtc: json['startUtc'] == null ? null : DateTime.tryParse(json['startUtc'].toString()),
      endUtc: json['endUtc'] == null ? null : DateTime.tryParse(json['endUtc'].toString()),

      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,

      // Hứng thêm dữ liệu địa điểm
      placeName: json['placeName'] as String?,
      placeAddress: json['placeAddress'] as String?,
    );
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }
}
// class lưu review địa điểm //
class PlaceReview {
  final int reviewId;
  final double rating;
  final String comment;
  final DateTime createdAtUtc;
  final String userName;

  PlaceReview({
    required this.reviewId,
    required this.rating,
    required this.comment,
    required this.createdAtUtc,
    required this.userName,
  });

  factory PlaceReview.fromJson(Map<String, dynamic> json) {
    // 1. Lấy chuỗi thời gian thô
    String rawDate = json['createdAtUtc']?.toString() ?? '';

    // 2.  Nếu chuỗi thiếu chữ 'Z' ở cuối, ta tự thêm vào
    // để Dart hiểu đây là giờ UTC chứ không phải giờ địa phương.
    if (rawDate.isNotEmpty && !rawDate.endsWith('Z')) {
      rawDate += 'Z';
    }

    return PlaceReview(
      reviewId: json['reviewId'] ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      comment: json['comment'] ?? '',

      // 3. Parse xong gọi .toLocal() để chuyển về múi giờ điện thoại (VN)
      createdAtUtc: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),

      userName: json['userName'] ?? 'Ẩn danh',
    );
  }

  // Cập nhật lại logic hiển thị thời gian cho tự nhiên hơn
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAtUtc);

    if (diff.inDays > 30) {
      // Nếu quá 30 ngày thì hiện ngày tháng năm
      return DateFormat('dd/MM/yyyy').format(createdAtUtc);
    }
    if (diff.inDays > 0) return '${diff.inDays} ngày trước';
    if (diff.inHours > 0) return '${diff.inHours} giờ trước';
    if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
    return 'Vừa xong';
  }
}
// =======================================================
// 2. MAIN PAGE
// =======================================================

class MapPage extends StatefulWidget {
  final int? accountId;
  final String? authToken;
  final MapPlace? initialTarget; // địa điểm hiển thị từ home_page//
  const MapPage({
    super.key,
    this.accountId,
    this.authToken,
    this.initialTarget
  });
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // === STATE VÀ CONTROLLERS ===
  final MapController _map = MapController();
  final TextEditingController _searchCtrl = TextEditingController(text: '');

  bool get _hasToken => (widget.authToken ?? '').isNotEmpty;

  late final _FoursquareClient _fsq;

  String get _searchHistoryEndpoint => '$baseUrl/me/search-history';
  String get _favoriteEndpoint => '$baseUrl/me/favorites';

  LatLng? _currentGpsLocation;
  bool _loading = false;
  List<MapPlace> _fetched = [];
  List<Marker> _markers = [];
  Marker? _targetMarker; //marker cho các địa điểm từ home_page

  SearchProvider _searchProvider = SearchProvider.osm;

  Map<String, Map<String, dynamic>>? _detailCache;
  bool _detailBusy = false;

  // State Quảng cáo
  List<Advertisement> _activeAds = [];
  Timer? _adLoadDebouncer;

  // State Chỉ đường
  List<LatLng> _routePoints = [];
  bool _isFetchingRoute = false;
  // Marker của đối tác
  List<Marker> _supplierMarkers = [];
  // === LIFECYCLE ===
  // Hàm này chỉ có nhiệm vụ TẠO và TRẢ VỀ Marker (không gọi setState)
  Marker _createTargetMarker(MapPlace p) {
    final bool isSupplier = p.supplierId != null;

    return Marker(
      point: LatLng(p.lat, p.lng),
      width: 60, height: 60,
      child: GestureDetector(
        onTap: () => _showPlaceSheet(p),
        child: isSupplier
            ? Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.star_rounded, color: Colors.orange, size: 36),
        )
            : Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            // boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: Icon(
            Icons.location_on,
            size: 50,
            color: CrystalTheme.accentPink,
          ),
        ),
      ),
    );
  }
  @override
  void initState() {
    super.initState();
    _fsq = _FoursquareClient(apiKey: foursquareApiKey);

    // Logic khởi tạo
    if (widget.initialTarget != null) {
      final p = widget.initialTarget!;

      // GỌI HÀM HELPER TẠO MARKER Ở TRÊN
      _targetMarker = _createTargetMarker(p);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPlaceSheet(p);
      });
      _ensureLocation(moveMap: false);
    } else {
      _ensureLocation(moveMap: true);
    }
  }
  // Hàm xử lý khi mở Map từ trang Đề xuất
  void _initTargetMode() {
    final p = widget.initialTarget!;

    // Logic xác định icon: Nếu có supplierId thì hiện Sao, còn lại hiện Pin Hồng
    final bool isSupplier = p.supplierId != null;

    final marker = Marker(
      point: LatLng(p.lat, p.lng),
      width: 60, height: 60,
      child: GestureDetector(
        onTap: () => _showPlaceSheet(p),
        child: isSupplier
            ? Container( // Icon Ngôi sao (Đối tác)
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: const Icon(Icons.star_rounded, color: Colors.orange, size: 36),
        )
            : Column( // Icon Pin Hồng
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                Icons.location_on,
                size: 50,
                color: CrystalTheme.accentPink,
                // shadows: const [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))]
            ),
          ],
        ),
      ),
    );

    setState(() {
      _targetMarker = marker; // Gán vào biến riêng tách biệt với marker trả về kết quả tìm kiếm từ hàm search
    });

    // Vẫn lấy GPS nền nhưng không di chuyển map
    _ensureLocation(moveMap: false);

    // Tự động mở thông tin chi tiết sau khi map load xong
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPlaceSheet(p);
    });
  }


  @override
  void dispose() {
    _map.dispose();
    _searchCtrl.dispose();
    _adLoadDebouncer?.cancel();
    super.dispose();
  }

  // === HELPERS ===

  Map<String, String> _authHeaders({Map<String, String>? more}) {
    return {
      if (_hasToken) 'Authorization': 'Bearer ${widget.authToken}',
      ...?more,
    };
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  //  hàm lưu lịch sử tìm kiếm
  Future<void> _saveSearchHistory(String keyword) async {
    if (!_hasToken || keyword.isEmpty) return;

    try {
      final headers = _authHeaders(more: {'Content-Type': 'application/json'});
      final body = jsonEncode({
        'keyword': keyword,
        'searchDate': DateTime.now().toUtc().toIso8601String()
      });

      // Gọi API ngầm, không cần await kết quả để chặn UI
      http.post(Uri.parse(_searchHistoryEndpoint), headers: headers, body: body)
          .then((resp) => debugPrint('[History] Saved "$keyword": ${resp.statusCode}'))
          .catchError((e) => debugPrint('[History] Error: $e'));

    } catch (e) {
      debugPrint('[History] Exception: $e');
    }
  }

  // --- LOCATION & ADS ---
  Future<void> _ensureLocation({bool moveMap = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { _toast('GPS chưa bật'); return; }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _toast('Không có quyền vị trí');
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      final newPos = LatLng(p.latitude, p.longitude);
      setState(() => _currentGpsLocation = newPos);
      _map.move(newPos, 14);

      if (mounted) {
        setState(() => _currentGpsLocation = newPos);

        // CHỈ DI CHUYỂN MAP NẾU ĐƯỢC PHÉP
        if (moveMap) {
          _map.move(newPos, 14);
          Timer(const Duration(seconds: 1), () {
            if(mounted) {
              final bounds = _map.camera.visibleBounds;
              _loadAdsInView(bounds);
              _loadSupplierPlacesInView(bounds);
            }
          });
        }
      }
    } catch (e) {
      _toast('Lấy vị trí lỗi: $e');
    }
  }

  // Hàm hiển thị marker địa điểm do đối tác đăng ký//
  Future<void> _loadSupplierPlacesInView(LatLngBounds? bounds) async {
    if (bounds == null) return;

    final query = 'north=${bounds.northEast.latitude}&south=${bounds.southWest.latitude}'
        '&east=${bounds.northEast.longitude}&west=${bounds.southWest.longitude}';
    final url = Uri.parse('$baseUrl/api/places/visible?$query');

    try {
      final response = await http.get(url, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final list = (json['data'] as List? ?? []);

        final newMarkers = list.map((item) {
          // Lấy SupplierId từ API
          final int? supId = item['supplierId'];

          if (supId == null) return null;

          final p = MapPlace(
            providerId: "internal_${item['placeId']}",
            name: item['name'] ?? 'Không tên',
            address: item['address'] ?? '',
            category: item['category'] ?? 'Địa điểm',
            lat: (item['latitude'] as num).toDouble(),
            lng: (item['longitude'] as num).toDouble(),
            supplierId: supId,
          );

          return Marker(
            point: LatLng(p.lat, p.lng),
            width: 30, height: 30,
            child: GestureDetector(
              onTap: () => _showPlaceSheet(p),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2))],
                  border: Border.all(color: Colors.orange, width: 1.5),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.orange, size: 28),
              ),
            ),
          );
        })
        // Lọc bỏ các giá trị null
            .whereType<Marker>()
            .toList();

        if (mounted) {
          setState(() {
            _supplierMarkers = newMarkers;
          });
        }
      }
    } catch (e) {
      debugPrint('[Supplier Loader] Error: $e');
    }
  }

  Future<void> _loadAdsInView(LatLngBounds? bounds) async {
    if (bounds == null) return;
    final query = 'north=${bounds.northEast.latitude}&south=${bounds.southWest.latitude}'
        '&east=${bounds.northEast.longitude}&west=${bounds.southWest.longitude}';
    final url = Uri.parse('$baseUrl/api/advertisements/active-in-bounds?$query');
    try {
      final response = await http.get(url, headers: _authHeaders(more: {'Accept': 'application/json'}));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final adList = (json is Map && json['data'] is List) ? json['data'] as List : [];
        if (mounted) {
          setState(() {
            _activeAds = adList.map((data) => Advertisement.fromJson(data)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('[Ad Loader] Error: $e');
    }
  }
  // ---  GỌI API LẤY CHI TIẾT QUẢNG CÁO ---
  Future<Advertisement?> _fetchAdDetail(int adId) async {
    // Nếu adId = 0 (do lỗi data) thì không gọi API
    if (adId == 0) return null;

    try {
      final url = Uri.parse('$baseUrl/api/advertisements/$adId');
      final resp = await http.get(url, headers: _authHeaders(more: {'Accept': 'application/json'}));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        // Backend có thể trả về { data: {...} } hoặc trực tiếp {...}
        final data = json['data'] != null ? json['data'] : json;
        return Advertisement.fromJson(data);
      } else {
        debugPrint("Lỗi tải chi tiết quảng cáo: ${resp.statusCode}");
      }
    } catch (e) {
      debugPrint("Exception tải chi tiết quảng cáo: $e");
    }
    return null;
  }

  void _onMapMoved(MapCamera camera, bool hasGesture) {
    if (_adLoadDebouncer?.isActive ?? false) _adLoadDebouncer!.cancel();
    _adLoadDebouncer = Timer(const Duration(milliseconds: 750), () {
      final bounds = camera.visibleBounds;
      _loadAdsInView(bounds);
      _loadSupplierPlacesInView(bounds);
    });
  }

  // --- ROUTING --- chỉ đường
  Future<void> _getRoute(LatLng start, LatLng end) async {
    if (mounted) setState(() { _isFetchingRoute = true; _routePoints.clear(); });

    // OSRM yêu cầu format: longitude,latitude
    final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson');

    try {
      // HEADER USER-AGENT
      final response = await http.get(url, headers: {
        'User-Agent': 'TourismApp/1.0 (com.example.tourismapp)',
      });

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        // Kiểm tra xem OSRM có trả về route nào không
        if (json['routes'] == null || (json['routes'] as List).isEmpty) {
          _toast('Không tìm thấy đường đi giữa 2 điểm này.');
          return;
        }

        final geometry = json['routes'][0]['geometry']['coordinates'];
        final List<LatLng> points = (geometry as List).map((p) => LatLng(p[1], p[0])).toList();

        if (mounted) {
          setState(() {
            _routePoints = points;
            // Zoom map để thấy toàn bộ đường đi
            if (points.isNotEmpty) {
              _map.fitCamera(CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points),
                  padding: const EdgeInsets.all(50)
              ));
            }
          });
        }
      } else {
        debugPrint('[OSRM Error] Status: ${response.statusCode}, Body: ${response.body}');
        _toast('Lỗi OSRM: Mã ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[OSRM Exception] $e');
      _toast('Lỗi kết nối tìm đường: $e');
    } finally {
      if (mounted) setState(() => _isFetchingRoute = false);
    }
  }

  // --- FAVORITES ---
  Future<void> _favoritePlace(MapPlace p) async {
    if (!_hasToken) { _toast('Cần đăng nhập để lưu yêu thích'); return; }
    final headers = _authHeaders(more: {'Content-Type': 'application/json'});
    final body = jsonEncode(p.toJson());
    try {
      final resp = await http.post(Uri.parse(_favoriteEndpoint), headers: headers, body: body);
      if (resp.statusCode == 200 || resp.statusCode == 201) _toast('Đã lưu yêu thích');
      else if (resp.statusCode == 409) _toast('Đã có trong yêu thích');
      else _toast('Lỗi lưu: ${resp.statusCode}');
    } catch (e) {
      _toast('Lỗi: $e');
    }
  }

  // =======================================================
  // --- SEARCH LOGIC  ---
  // =======================================================
  Future<void> _search({bool triggeredByUser = false}) async {
    FocusScope.of(context).unfocus();

    if (triggeredByUser) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    final bounds = _map.camera.visibleBounds;
    final center = _map.camera.center;
    final q = _searchCtrl.text.trim();

    if (q.isEmpty) return; // Nếu bounds chưa sẵn sàng thì bỏ qua check bounds ở đây để internal vẫn chạy được

    setState(() {
      _loading = true;
      _markers = [];
      _fetched = [];
      _routePoints = [];
    });

    try {
      // 1. GỌI TÌM KIẾM NỘI BỘ (SQL)
      final internalResults = await _searchInternal(q);

      // 2. GỌI TÌM KIẾM BÊN NGOÀI (Foursquare/OSM)
      List<MapPlace> externalResults = [];
      debugPrint("========== SEARCH ==========");
      debugPrint("Keyword: $q");
      debugPrint("Internal: ${internalResults.length}");
      for (final p in internalResults) {
        debugPrint("[IN] ${p.name}");
      }

      // Chỉ tìm bên ngoài nếu map đã load xong bounds
      if (bounds != null && bounds.northEast != bounds.southWest) {
        if (_searchProvider == SearchProvider.foursquare) {
          externalResults = await _searchFoursquare(q, center);
        } else {
          externalResults = await _searchOverpass(q, bounds);
        }
      }

      debugPrint("External: ${externalResults.length}");
      for (final p in externalResults) {
        debugPrint("[OUT] ${p.name}");
      }

      // 3. GỘP KẾT QUẢ (Ưu tiên kết quả nội bộ lên đầu)
      final allPlaces = [...internalResults, ...externalResults];

      if (mounted) {
        _useResults(allPlaces, triggeredByUser, q);
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) {
        setState(() => _loading = false);
        _toast('Lỗi tìm kiếm: $e');
      }
    }
  }
  // Hàm tìm kiếm trong SQL Database
  Future<List<MapPlace>> _searchInternal(String query) async {
    try {
      final url = Uri.parse('$baseUrl/api/places/search?keyword=${Uri.encodeComponent(query)}');
      final resp = await http.get(url, headers: {'Accept': 'application/json'});
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final listData = json['data'] as List? ?? [];
        return listData.map((item) {
          return MapPlace(
            providerId: "internal_${item['placeId']}",
            name: item['name'] ?? '',
            address: item['address'] ?? '',
            category: item['category'] ?? 'Địa điểm',
            lat: (item['latitude'] as num).toDouble(),
            lng: (item['longitude'] as num).toDouble(),
            supplierId: item['supplierId'], // [THÊM]
          );
        }).toList();
      }
    } catch (e) { debugPrint("Lỗi tìm kiếm nội bộ: $e"); }
    return [];
  }

  Future<List<MapPlace>> _searchFoursquare(String query, LatLng center) async {
    try {
      final qLower = query.toLowerCase();
      String? categories;
      if (qLower.contains('coffee') || qLower.contains('cafe') || qLower.contains('cà phê')) {
        categories = "4bf58dd8d48988d1e0931735,4bf58dd8d48988d16d941735";
      }
      final res = await _fsq.search(query: query, center: center, categories: categories);
      return _parseFsqResults(res);
    } catch (e) {
      debugPrint("Lỗi search Foursquare: $e");
      return [];
    }
  }
  static const Map<String, List<String>> _osmSearchMap = {
    // Cafe
    'cafe': [
      'amenity=cafe',
      'shop=coffee',
    ],
    'coffee': [
      'amenity=cafe',
      'shop=coffee',
    ],
    'cà phê': [
      'amenity=cafe',
      'shop=coffee',
    ],

    // Restaurant
    'restaurant': [
      'amenity=restaurant',
      'amenity=fast_food',
    ],
    'nhà hàng': [
      'amenity=restaurant',
      'amenity=fast_food',
    ],
    'quán ăn': [
      'amenity=restaurant',
      'amenity=fast_food',
    ],

    // Hotel
    'hotel': [
      'tourism=hotel',
      'tourism=guest_house',
    ],
    'khách sạn': [
      'tourism=hotel',
      'tourism=guest_house',
    ],

    // Hospital
    'hospital': [
      'amenity=hospital',
    ],
    'bệnh viện': [
      'amenity=hospital',
    ],

    // ATM
    'atm': [
      'amenity=atm',
    ],

    // Bank
    'bank': [
      'amenity=bank',
    ],
    'ngân hàng': [
      'amenity=bank',
    ],

    // School
    'school': [
      'amenity=school',
    ],
    'trường': [
      'amenity=school',
    ],

    // Park
    'park': [
      'leisure=park',
    ],
    'công viên': [
      'leisure=park',
    ],

    // Museum
    'museum': [
      'tourism=museum',
    ],
    'bảo tàng': [
      'tourism=museum',
    ],

    // Temple
    'temple': [
      'amenity=place_of_worship',
    ],
    'chùa': [
      'amenity=place_of_worship',
    ],
  };
  Future<List<MapPlace>> _searchOverpass(
      String query,
      LatLngBounds bounds,
      ) async {
    try {
      double s = bounds.southWest.latitude;
      double w = bounds.southWest.longitude;
      double n = bounds.northEast.latitude;
      double e = bounds.northEast.longitude;

      if ((n - s).abs() < 0.001) {
        s -= 0.01;
        n += 0.01;
        w -= 0.01;
        e += 0.01;
      }

      final bbox = '$s,$w,$n,$e';

      final qLower = query.toLowerCase().trim();
      final escaped = query.replaceAll('"', '\\"');

      List<String>? matchedTags;

      for (final entry in _osmSearchMap.entries) {
        if (qLower.contains(entry.key)) {
          matchedTags = entry.value;
          break;
        }
      }

      String queryBody;

      if (matchedTags != null) {
        queryBody = matchedTags.map((tag) {
          final parts = tag.split('=');

          return 'nwr["${parts[0]}"="${parts[1]}"]($bbox);';
        }).join('\n');
      } else {
        queryBody = '''
      nwr["name"~"$escaped",i]($bbox);
      ''';
      }

      final finalQuery = '''
[out:json][timeout:25];
(
$queryBody
);
out center;
''';

      final uri = Uri.parse(
        'https://overpass-api.de/api/interpreter',
      );

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'TourismApp/1.0',
        },
        body: {
          'data': finalQuery,
        },
      );

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);

      return _parseOverpassResults(decoded);
    } catch (e) {
      debugPrint('Overpass Error: $e');
      return [];
    }
  }

  List<MapPlace> _parseFsqResults(Map<String, dynamic> body) {
    final results = List<Map<String, dynamic>>.from(body['results'] ?? []);
    final places = <MapPlace>[];
    for (final m in results) {
      final id = m['fsq_id'] ?? m['fsq_place_id'];
      if (id == null) continue;
      final name = m['name'] ?? '';
      final address = m['location']?['formatted_address'] ?? '';
      final cats = m['categories'] as List? ?? [];
      final category = cats.isNotEmpty ? (cats.first['name'] ?? '') : '';
      double? lat = m['geocodes']?['main']?['latitude'] ?? m['location']?['lat'];
      double? lng = m['geocodes']?['main']?['longitude'] ?? m['location']?['lng'];
      if (lat == null || lng == null) continue;
      places.add(MapPlace(providerId: "fsq_$id", name: name, address: address, category: category, lat: lat, lng: lng));
    }
    return places;
  }

  List<MapPlace> _parseOverpassResults(Map<String, dynamic> json) {
    final elements = List<Map<String, dynamic>>.from(json['elements'] ?? []);
    final places = <MapPlace>[];
    for (final m in elements) {
      final id = m['id']?.toString();
      if (id == null) continue;
      final tags = m['tags'] as Map<String, dynamic>?;
      if (tags == null) continue;
      final name = tags['name'] ?? 'Địa điểm không tên';
      final address = [tags['addr:housenumber'], tags['addr:street'], tags['addr:city']].where((s) => s != null).join(', ');
      final category = tags['amenity'] ?? tags['tourism'] ?? 'Địa điểm';
      double? lat = m['lat'] ?? m['center']?['lat'];
      double? lng = m['lon'] ?? m['center']?['lon'];
      if (lat == null || lng == null) continue;
      places.add(MapPlace(providerId: "osm_$id", name: name, address: address.isEmpty ? (tags['name:en'] ?? "Gần đây") : address, category: category, lat: lat, lng: lng));
    }
    return places;
  }

  void _useResults(List<MapPlace> places, bool triggeredByUser, String q) {
    if (places.isEmpty) {
      setState(() { _loading = false; _markers = []; _fetched = []; });
      _toast('Không tìm thấy kết quả.');
      return;
    }

    final markers = places.map((p) {
      // Địa điểm Đối tác (Có SupplierId) -> Marker Ngôi Sao//
      if (p.supplierId != null) {
        return Marker(
          point: LatLng(p.lat, p.lng),
          width: 48, height: 48,
          child: GestureDetector(
            onTap: () => _showPlaceSheet(p),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: const Icon(Icons.star_rounded, color: Colors.orange, size: 32),
            ),
          ),
        );
      }

      // Tất cả địa điểm còn lại (Foursquare, OSM, Admin Internal) -> Marker Blue Crystal//
      return Marker(
        point: LatLng(p.lat, p.lng),
        width: 48, height: 48,
        child: GestureDetector(
          onTap: () => _showPlaceSheet(p),
          child: Column(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 40,
                // Force màu xanh Crystal cho tất cả các loại còn lại
                color: CrystalTheme.primaryBlue,
                shadows: const [Shadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 3))],
              ),
            ],
          ),
        ),
      );
    }).toList();

    setState(() { _fetched = places; _markers = markers; _loading = false; });

    if (triggeredByUser && q.isNotEmpty && _hasToken) {
      _saveSearchHistory(q);
    }
  }

  Future<Map<String, dynamic>?> _fetchPlaceDetailsLite(String fsqId) async {
    if (!fsqId.startsWith('fsq_')) return null;
    final realId = fsqId.substring(4);
    _detailCache ??= {};
    if (_detailCache!.containsKey(realId)) return _detailCache![realId];
    try {
      final uri = Uri.parse('https://places-api.foursquare.com/places/$realId?fields=name,location,categories,website,tel');
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer ${_fsq.apiKey.trim()}','Accept': 'application/json'});
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        _detailCache![realId] = json;
        return json;
      }
    } catch (e) { /* ignore */ }
    return null;
  }

  // =======================================================
// 3. LOGIC REVIEW (ĐÃ GIỮ NGUYÊN FIX PROVIDER ID)
// =======================================================

  Future<void> _submitReview(MapPlace p, double rating, String comment, {VoidCallback? onSuccess}) async {
    if (!_hasToken) {
      _toast('Vui lòng đăng nhập để đánh giá.');
      return;
    }

    try {
      final url = Uri.parse('$baseUrl/api/reviews');
      final headers = _authHeaders(more: {'Content-Type': 'application/json'});

      // --- SỬA LOGIC XỬ LÝ ID ĐỂ KHỚP VỚI toJson() ---
      String cleanProviderId = p.providerId;
      String providerName = 'google';

      if (p.providerId.startsWith('fsq_')) {
        providerName = 'foursquare';
        cleanProviderId = p.providerId.substring(4);
      } else if (p.providerId.startsWith('osm_')) {
        providerName = 'osm';
        cleanProviderId = p.providerId.substring(4);
      } else if (p.providerId.startsWith('internal_')) {
        providerName = 'internal';
        cleanProviderId = p.providerId.substring(9);
      }

      final body = jsonEncode({
        'rating': rating,
        'comment': comment,
        'provider': providerName,
        'providerId': cleanProviderId, // <--- DÙNG ID ĐÃ CẮT
        'name': p.name,
        'address': p.address,
        'category': p.category,
        'latitude': p.lat,
        'longitude': p.lng,
      });

      print("DEBUG: Gửi Review với Provider: $providerName - ID: $cleanProviderId");

      final resp = await http.post(url, headers: headers, body: body);

      if (!mounted) return;

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _toast('Đánh giá thành công!');

        // Delay nhẹ để DB kịp commit dữ liệu
        await Future.delayed(const Duration(milliseconds: 500));

        if (onSuccess != null) {
          onSuccess();
        }
      } else if (resp.statusCode == 409) {
        _toast('Bạn đã đánh giá địa điểm này rồi.');
      } else if (resp.statusCode == 401) {
        _toast('Phiên đăng nhập hết hạn.');
      } else {
        _toast('Lỗi: ${resp.statusCode}');
        print("Lỗi Server: ${resp.body}");
      }
    } catch (e) {
      _toast('Lỗi kết nối: $e');
    }
  }

// Hàm mở Dialog giữ nguyên, chỉ gọi _submitReview mới
  void _openReviewDialog(MapPlace p, {VoidCallback? onSuccess}) {
    showDialog(
      context: context,
      builder: (ctx) => _ReviewDialog(
        placeName: p.name,
        onSubmit: (rating, comment) {
          Navigator.of(ctx).pop(); // Đóng dialog nhập liệu
          // Gọi hàm submit kèm theo callback onSuccess
          _submitReview(p, rating, comment, onSuccess: onSuccess);
        },
      ),
    );
  }

  // =======================================================
  // 4. UI SHEETS (CRYSTAL STYLED)
  // =======================================================
  void _showAdSheet(Advertisement summaryAd) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65, // Tăng chiều cao lên chút
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: FutureBuilder<Advertisement?>(
              // GỌI HÀM LẤY CHI TIẾT TẠI ĐÂY
              future: _fetchAdDetail(summaryAd.adId),
              builder: (context, snapshot) {
                // Ưu tiên dùng dữ liệu mới tải về (full), nếu chưa có thì dùng bản tóm tắt (summary)
                final ad = snapshot.data ?? summaryAd;
                final bool isLoading = snapshot.connectionState == ConnectionState.waiting;

                return Column(
                  children: [
                    // Handle bar (Thanh nắm kéo)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),

                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          // 1. ẢNH BANNER
                          if (ad.bannerImageUrl != null && ad.bannerImageUrl!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                ad.bannerImageUrl!,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 150, color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),

                          // 2. TIÊU ĐỀ
                          Text(
                            ad.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
                          ),
                          const SizedBox(height: 12),

                          // 3. THÔNG TIN ĐỊA ĐIỂM (Place) - MỚI
                          if (ad.placeName != null || ad.placeAddress != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.withOpacity(0.1)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.storefront, color: CrystalTheme.primaryBlue, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (ad.placeName != null)
                                          Text(ad.placeName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                        if (ad.placeAddress != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(ad.placeAddress!, style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.3)),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          // 4. THỜI GIAN
                          if (ad.startUtc != null && ad.endUtc != null)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Kết thúc: ${ad.formatDate(ad.endUtc)}",
                                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // 5. MÔ TẢ CHI TIẾT (Description)
                          Text("Chi tiết ưu đãi:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
                          const SizedBox(height: 8),

                          if (isLoading)
                          // Hiệu ứng Loading
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(children: const [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text("Đang tải nội dung đầy đủ...", style: TextStyle(color: Colors.grey))
                              ]),
                            )
                          else if (ad.description != null && ad.description!.isNotEmpty)
                            Text(ad.description!, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5))
                          else
                            const Text("Không có mô tả thêm.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),

                    // Nút bấm (Giữ nguyên)
                    Container(
                      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
                      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                if (ad.latitude != null) _map.move(LatLng(ad.latitude!, ad.longitude!), 17);
                              },
                              icon: const Icon(Icons.my_location),
                              label: const Text("Vị trí"),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                if (_currentGpsLocation != null && ad.latitude != null) {
                                  _getRoute(_currentGpsLocation!, LatLng(ad.latitude!, ad.longitude!));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chưa lấy được vị trí của bạn")));
                                }
                              },
                              style: FilledButton.styleFrom(backgroundColor: CrystalTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              icon: const Icon(Icons.directions, color: Colors.white),
                              label: const Text("Đi ngay"),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }


  void _showPlaceSheet(MapPlace p) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceDetailSheet(
        place: p,
        currentLocation: _currentGpsLocation,
        onFavorite: () => _favoritePlace(p),
        onRoute: (dest) => _getRoute(_currentGpsLocation!, dest),
        onReviewTap: (VoidCallback onRefresh) {
          _openReviewDialog(p, onSuccess: onRefresh);
        },
        // Truyền các hàm phụ trợ cần thiết vào
        authHeaders: _authHeaders(),
      ),
    );
  }

  // Helper tạo nút bấm phong cách pha lê
  Widget _buildCrystalButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    bool isPrimary = true,
    bool isSpecial = false,
    bool compact = false,
  }) {
    Gradient bgGradient;
    Color iconColor;

    if (isSpecial) {
      bgGradient = const LinearGradient(colors: [Color(0xFFFFCC80), Color(0xFFFFE0B2)]); // Cam nhạt cho đánh giá
      iconColor = Colors.brown;
    } else if (isPrimary) {
      bgGradient = CrystalTheme.blueGradient;
      iconColor = Colors.white;
    } else {
      bgGradient = CrystalTheme.pinkGradient;
      iconColor = Colors.white;
    }

    return Container(
      height: compact ? 40 : 48,
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        boxShadow: [
          BoxShadow(
            color: (isPrimary ? CrystalTheme.primaryBlue : CrystalTheme.accentPink).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(compact ? 20 : 24),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: isSpecial ? Colors.brown : Colors.white, size: compact ? 18 : 22),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: isSpecial ? Colors.brown : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 13 : 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =======================================================
  // 5. BUILD UI
  // =======================================================
  @override
  Widget build(BuildContext context) {
    LatLng center;
    if (widget.initialTarget != null) {
      center = LatLng(widget.initialTarget!.lat, widget.initialTarget!.lng);
    } else {
      center = _currentGpsLocation ?? const LatLng(10.776889, 106.700806);
    }
    final settingsProvider = context.watch<DownloadConfigurationProvider>();
    final browsingStrategy = settingsProvider.enableBrowsingCache ? BrowseStoreStrategy.readUpdateCreate : BrowseStoreStrategy.read;

    return Scaffold(
      extendBodyBehindAppBar: true, // Để map tràn lên full màn hình
      appBar: AppBar(
        title: const Text('Khám phá', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent, // Trong suốt để dùng gradient
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
              gradient: CrystalTheme.blueGradient.scale(1.0),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _search(triggeredByUser: true),
            icon: const Icon(Icons.search, color: Colors.white),
          ),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: center, initialZoom: 13, onPositionChanged: _onMapMoved),
          children: [
            TileLayer(
              urlTemplate: kMapUrlTemplate,
              userAgentPackageName: 'com.example.tourismapp',
              maxZoom: 19,
              tileProvider: FMTCTileProvider(
                loadingStrategy: BrowseLoadingStrategy.cacheFirst,
                stores: {
                  kMainMapStoreName: BrowseStoreStrategy.read,
                  kBrowsingCacheStoreName: browsingStrategy,
                },
              ),
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: _routePoints,
                  color: CrystalTheme.primaryBlue, // Đường đi màu xanh pha lê
                  strokeWidth: 5,
                  borderColor: Colors.white,
                  borderStrokeWidth: 2,
                )
              ]),
            MarkerLayer(markers: [
              if (_targetMarker != null) _targetMarker!,
              // 1. Marker của Đối tác/Supplier (Luôn hiện, icon ngôi sao)
              ..._supplierMarkers,

              // 2. Marker kết quả tìm kiếm (Hiện khi người dùng search)
              ..._markers,

              // 3. Marker Quảng cáo (Ads Custom Style)
              ..._activeAds.map((ad) {
                if (ad.latitude == null || ad.longitude == null) return null;

                // Kiểm tra xem có ảnh Banner không
                final hasImage = ad.bannerImageUrl != null && ad.bannerImageUrl!.isNotEmpty;

                return Marker(
                  point: LatLng(ad.latitude!, ad.longitude!),
                  // Nếu có ảnh thì Marker to hơn, không có ảnh thì nhỏ gọn
                  width: hasImage ? 100 : 60,
                  height: hasImage ? 70 : 50,
                  child: GestureDetector(
                    onTap: () => _showAdSheet(ad),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                        // Nếu không có ảnh thì dùng Gradient cam như cũ
                        gradient: hasImage ? null : const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFFFB74D)]),
                      ),
                      child: hasImage
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(10), // Bo góc cho ảnh bên trong
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Ảnh nền
                            Image.network(
                              ad.bannerImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Nếu ảnh lỗi thì hiện nền xám
                                return Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey));
                              },
                            ),
                            // 2. Lớp phủ đen mờ ở dưới để title dễ đọc
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                                  ),
                                ),
                              ),
                            ),
                            // 3. Title đè lên ảnh
                            Positioned(
                              bottom: 4, left: 8, right: 8,
                              child: Text(
                                ad.title,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                      // Nếu không có ảnh -> Hiện Text trên nền cam
                          : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            ad.title,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).whereType<Marker>().toList(),

              // 4. Vị trí người dùng (User Location Custom Style)
              if (_currentGpsLocation != null)
                Marker(
                    point: _currentGpsLocation!,
                    width: 24, height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: CrystalTheme.primaryBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
                      ),
                    )
                ),
            ]),
          ],
        ),

        // SEARCH BAR (Crystal Style) - ĐÃ SỬA NÚT RESET
        Positioned(
          left: 16, right: 16, top: 100, // Đẩy xuống dưới AppBar custom
          child: _SearchBar(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            onSubmit: (_) => _search(triggeredByUser: true),

            // --- FIX: LOGIC RESET SẠCH SẼ ---
            onClear: () {
              _searchCtrl.clear();
              setState(() {
                _markers = [];
                _fetched = [];
                _routePoints = []; // Xóa đường đi cũ
              });
              FocusScope.of(context).unfocus(); // Đóng bàn phím
            },
            // --------------------------------

            onMyLocation: () async => _ensureLocation(),
            initialProvider: _searchProvider,
            onProviderChanged: (p) { setState(() => _searchProvider = p); if(_searchCtrl.text.isNotEmpty) _search(triggeredByUser: true); },
            enableBrowsingCache: settingsProvider.enableBrowsingCache,
            onBrowsingCacheChanged: (val) => settingsProvider.toggleBrowsingCache(val),
          ),
        ),
        if (_loading) const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue)),
      ]),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_dl',
        backgroundColor: Colors.white,
        elevation: 4,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineMapsPage())),
        child: Icon(Icons.download_for_offline_rounded, color: CrystalTheme.primaryBlue), // Icon màu xanh
      ),
    );
  }
}

// =======================================================
// 6. SEARCH BAR WIDGET (CRYSTAL STYLE)
// =======================================================
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final void Function(String) onSubmit;
  final VoidCallback onClear;
  final VoidCallback onMyLocation;
  final SearchProvider initialProvider;
  final void Function(SearchProvider) onProviderChanged;
  final bool enableBrowsingCache;
  final void Function(bool) onBrowsingCacheChanged;

  const _SearchBar({
    required this.controller, required this.onChanged, required this.onSubmit, required this.onClear,
    required this.onMyLocation, required this.initialProvider, required this.onProviderChanged,
    required this.enableBrowsingCache, required this.onBrowsingCacheChanged
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CrystalTheme.glassDecoration, // Áp dụng style kính pha lê
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Tìm kiếm địa điểm...',
              hintStyle: TextStyle(color: Colors.blueGrey[300]),
              prefixIcon: IconButton(icon: Icon(Icons.my_location, color: CrystalTheme.primaryBlue), onPressed: onMyLocation),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: onClear)
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
          ),
          Container(height: 1, color: Colors.grey[200]), // Divider mờ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              Text('Cache Map:', style: TextStyle(fontSize: 12, color: Colors.blueGrey[600])),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: enableBrowsingCache,
                  onChanged: onBrowsingCacheChanged,
                  activeColor: CrystalTheme.primaryBlue,
                  activeTrackColor: CrystalTheme.lightBlueBg,
                ),
              ),
              const Spacer(),
              _buildProviderToggle(),
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildProviderToggle() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _toggleButton('Bản đồ', SearchProvider.osm),
          _toggleButton('Gợi ý', SearchProvider.foursquare),
        ],
      ),
    );
  }

  Widget _toggleButton(String text, SearchProvider provider) {
    final isSelected = initialProvider == provider;
    return GestureDetector(
      onTap: () => onProviderChanged(provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black12, blurRadius: 2)] : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? CrystalTheme.primaryBlue : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// =======================================================
// 7. REVIEW DIALOG WIDGET (CRYSTAL STYLE)
// =======================================================
class _ReviewDialog extends StatefulWidget {
  final String placeName;
  final Function(double rating, String comment) onSubmit;

  const _ReviewDialog({required this.placeName, required this.onSubmit});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  double _rating = 5.0;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Đánh giá', style: TextStyle(color: Colors.blueGrey[300], fontSize: 14)),
            const SizedBox(height: 8),
            Text(widget.placeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF37474F)), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _rating = (index + 1).toDouble()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: index < _rating ? const Color(0xFFFFB300) : Colors.grey[300], // Vàng pha lê
                      size: 36,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _commentCtrl,
              decoration: InputDecoration(
                labelText: 'Nhận xét của bạn...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: CrystalTheme.primaryBlue)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                )),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: CrystalTheme.blueGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onSubmit(_rating, _commentCtrl.text);
                        // Navigator.pop(context); // Đã comment theo logic mới
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text('Gửi đánh giá', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// =======================================================
// 8. PLACE DETAIL SHEET (ĐÃ GIỮ NGUYÊN LOGIC REFRESH)
// =======================================================
class _PlaceDetailSheet extends StatefulWidget {
  final MapPlace place;
  final LatLng? currentLocation;
  final VoidCallback onFavorite;
  final Function(LatLng) onRoute;
  final Function(VoidCallback onRefresh) onReviewTap; // Chú ý dòng này
  final Map<String, String> authHeaders;

  const _PlaceDetailSheet({
    super.key,
    required this.place,
    this.currentLocation,
    required this.onFavorite,
    required this.onRoute,
    required this.onReviewTap,
    required this.authHeaders,
  });

  @override
  State<_PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<_PlaceDetailSheet> {
  List<PlaceReview> _reviews = [];
  bool _isLoadingReviews = true;
  double _averageRating = 5.0;
  int _totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  // Thêm tham số forceRefresh
  Future<void> _fetchReviews({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Nếu làm mới, bật trạng thái loading lên để UI thay đổi
    if (forceRefresh) {
      setState(() => _isLoadingReviews = true);
    }

    try {
      // 1. Lấy Internal ID
      final checkUrl = Uri.parse('$baseUrl/api/places/import');
      // Dùng cú pháp Spread Operator (...) để thêm header chuẩn
      final headers = {
        ...widget.authHeaders,
        'Content-Type': 'application/json'
      };

      final checkBody = jsonEncode(widget.place.toJson());
      final checkResp = await http.post(checkUrl, headers: headers, body: checkBody);

      int internalId = 0;
      if (checkResp.statusCode == 200 || checkResp.statusCode == 201) {
        final json = jsonDecode(checkResp.body);
        internalId = json['placeId'] is int ? json['placeId'] : int.tryParse(json['placeId'].toString()) ?? 0;
      }

      if (internalId == 0) {
        if (mounted) setState(() => _isLoadingReviews = false);
        return;
      }

      // 2. Lấy danh sách Review
      final reviewUrl = Uri.parse('$baseUrl/api/reviews/place/$internalId');

      final reviewResp = await http.get(reviewUrl, headers: widget.authHeaders);

      if (reviewResp.statusCode == 200) {
        final json = jsonDecode(reviewResp.body);
        final listData = json['data'] as List? ?? [];
        final reviews = listData.map((e) => PlaceReview.fromJson(e)).toList();

        double avg = 5.0;
        if (reviews.isNotEmpty) {
          final sum = reviews.fold(0.0, (prev, r) => prev + r.rating);
          avg = sum / reviews.length;
        }

        if (mounted) {
          setState(() {
            _reviews = reviews;
            _totalReviews = reviews.length;
            _averageRating = avg;
            _isLoadingReviews = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingReviews = false);
      }
    } catch (e) {
      debugPrint("Error fetching reviews: $e");
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(widget.place.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF37474F))),
          const SizedBox(height: 8),

          // Rating & Category
          Row(
            children: [
              if (widget.place.category.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(widget.place.category, style: TextStyle(color: CrystalTheme.primaryBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
              ],
              Icon(Icons.star_rounded, color: const Color(0xFFFFB300), size: 18),
              const SizedBox(width: 4),
              Text(_averageRating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(_totalReviews > 0 ? " ($_totalReviews đánh giá)" : " (Mới)", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.place.address.isNotEmpty)
            Row(children: [Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[600]), const SizedBox(width: 8), Expanded(child: Text(widget.place.address, style: TextStyle(color: Colors.blueGrey[700])))],),
          const SizedBox(height: 24),

          // --- BUTTONS ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _buildBtn('Lưu', Icons.favorite_border, false, widget.onFavorite),
              const SizedBox(width: 10),
              if (widget.currentLocation != null) ...[
                _buildBtn('Chỉ đường', Icons.directions_outlined, true, () { Navigator.pop(context); widget.onRoute(LatLng(widget.place.lat, widget.place.lng)); }),
                const SizedBox(width: 10),
              ],

              // --- NÚT ĐÁNH GIÁ ---
              _buildBtn('Đánh giá', Icons.star_border, false, () {
                // Không đóng sheet, gọi callback refresh
                widget.onReviewTap(() {
                  _fetchReviews(forceRefresh: true);
                });
              }, isSpecial: true),
              // ---------------------------
            ]),
          ),

          const SizedBox(height: 20), const Divider(),
          const Text("Đánh giá từ cộng đồng", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // Review List
          if (_isLoadingReviews)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_reviews.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Chưa có đánh giá nào", style: TextStyle(color: Colors.grey))))
          else Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _reviews.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _reviews[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Text(r.userName.isNotEmpty ? r.userName[0].toUpperCase() : '?', style: TextStyle(color: CrystalTheme.primaryBlue, fontWeight: FontWeight.bold))
                    ),
                    title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(r.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(r.timeAgo, style: const TextStyle(fontSize: 12, color: Colors.grey))
                    ]),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: List.generate(5, (index) => Icon(index < r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 14, color: Colors.amber))),
                      const SizedBox(height: 4),
                      Text(r.comment),
                    ]),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  Widget _buildBtn(String text, IconData icon, bool isPrimary, VoidCallback onTap, {bool isSpecial = false}) {
    // (Giữ nguyên code hàm _buildBtn của bạn)
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: isSpecial ? const LinearGradient(colors: [Color(0xFFFFCC80), Color(0xFFFFE0B2)]) : (isPrimary ? CrystalTheme.blueGradient : CrystalTheme.pinkGradient),
        ),
        child: Row(children: [Icon(icon, size: 18, color: isSpecial ? Colors.brown : Colors.white), const SizedBox(width: 8), Text(text, style: TextStyle(color: isSpecial ? Colors.brown : Colors.white, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}