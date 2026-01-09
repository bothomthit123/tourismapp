import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:tourismapp/Conts/api_config.dart';
import 'package:tourismapp/screens/map_page.dart'; // Import MapPage và MapPlace
import 'package:intl/intl.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';

class HomePage extends StatefulWidget {
  final int? accountId;
  final String? authToken;

  const HomePage({super.key, this.accountId, this.authToken});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> _recommendations = [];
  bool _loadingRec = true;
  String _recReason = "";

  List<dynamic> _activeAds = [];
  bool _loadingAds = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchRecommendations();
    _fetchActiveAds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- API CALLS ---
  Future<void> _fetchRecommendations() async {
    try {
      final headers = {
        if (widget.authToken != null) 'Authorization': 'Bearer ${widget.authToken}',
      };

      final uri = Uri.parse('$baseUrl/api/recommendations');
      final resp = await http.get(uri, headers: headers);

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);

        // Logic khử trùng lặp
        final List<dynamic> rawData = json['data'] ?? [];
        final Set<String> seenNames = {};
        final List<dynamic> uniqueData = [];

        for (var place in rawData) {
          final String name = place['name']?.toString() ?? '';
          if (name.isNotEmpty && !seenNames.contains(name)) {
            seenNames.add(name);
            uniqueData.add(place);
          }
        }

        if (mounted) {
          setState(() {
            _recommendations = uniqueData;
            _recReason = json['reason'] ?? "";
            _loadingRec = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingRec = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRec = false);
    }
  }

  Future<void> _fetchActiveAds() async {
    try {
      final uri = Uri.parse('$baseUrl/api/advertisements/active');
      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final adList = (json is Map && json['data'] is List) ? json['data'] as List : [];
        if (mounted) {
          setState(() {
            _activeAds = adList;
            _loadingAds = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingAds = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingAds = false);
    }
  }

  // --- NAVIGATION HANDLERS ---

  // 1. Xử lý click vào Đề xuất
  void _onRecommendationTap(dynamic item) {
    final double? lat = (item['latitude'] as num?)?.toDouble();
    final double? lng = (item['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) return;

    final targetPlace = MapPlace(
      providerId: item['providerId']?.toString() ?? "internal_${item['placeId']}",
      name: item['name'] ?? 'Địa điểm',
      address: item['address'] ?? '',
      category: item['category'] ?? 'Địa điểm',
      lat: lat,
      lng: lng,
      supplierId: item['supplierId'],
    );

    _navigateToMap(targetPlace);
  }

  // 2. Xử lý click vào Quảng cáo/Ưu đãi
  void _onAdTap(dynamic ad) {
    // Kiểm tra xem quảng cáo có gắn với tọa độ không
    final double? lat = (ad['latitude'] as num?)?.toDouble();
    final double? lng = (ad['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chương trình này chưa có thông tin vị trí cụ thể.")),
      );
      return;
    }

    // Tạo MapPlace từ thông tin Quảng cáo
    final targetPlace = MapPlace(
      providerId: "internal_${ad['placeId']}", // ID của quán gắn với quảng cáo
      name: ad['placeName'] ?? ad['title'] ?? 'Sự kiện',
      address: ad['placeAddress'] ?? '',
      category: 'Sự kiện',
      lat: lat,
      lng: lng,
      supplierId: ad['supplierId'], // Gán supplierId để hiện ngôi sao
    );

    _navigateToMap(targetPlace);
  }

  // Hàm chung để chuyển trang
  void _navigateToMap(MapPlace target) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPage(
          accountId: widget.accountId,
          authToken: widget.authToken,
          initialTarget: target, // Truyền địa điểm cần hiển thị marker
        ),
      ),
    );
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE1F5FE), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.blueGrey,
                  indicator: BoxDecoration(
                    gradient: CrystalTheme.blueGradient,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  tabs: const [
                    Tab(text: "Gợi ý cho bạn"),
                    Tab(text: "Sự kiện & Ưu đãi"),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecommendationTab(),
                    _buildAdsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Xin chào,", style: GoogleFonts.lato(fontSize: 16, color: Colors.blueGrey)),
              Text("Người lữ hành 👋", style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold, color: CrystalTheme.textDark)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: CrystalTheme.primaryBlue, width: 2)),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.grey),
            ),
          )
        ],
      ),
    );
  }

  // --- TAB 1: RECOMMENDATION VIEW ---
  Widget _buildRecommendationTab() {
    if (_loadingRec) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));

    if (_recommendations.isEmpty) {
      return const Center(child: Text("Chưa có đề xuất nào.", style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _fetchRecommendations,
      color: CrystalTheme.primaryBlue,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          _buildSectionTitle(
            _recReason == 'ai_personalized' ? 'Dành riêng cho bạn' : 'Địa điểm nổi bật',
            Icons.stars_rounded,
            Colors.amber,
          ),
          const SizedBox(height: 16),
          ..._recommendations.map((item) => _buildPlaceCard(item)).toList(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(dynamic item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => _onRecommendationTap(item), // Đã gắn hàm
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: Image.network(
                item['imageUrl'] ?? 'https://via.placeholder.com/100',
                width: 100, height: 100, fit: BoxFit.cover,
                errorBuilder: (_,__,___) => Container(width: 100, height: 100, color: Colors.grey[200], child: const Icon(Icons.image)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(item['address'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text("${item['rating']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Text("(${item['reviewCount']})", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- TAB 2: ADS VIEW ---
  Widget _buildAdsTab() {
    if (_loadingAds) return const Center(child: CircularProgressIndicator(color: CrystalTheme.accentPink));

    if (_activeAds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.event_busy, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text("Hiện không có chương trình nào.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchActiveAds,
      color: CrystalTheme.accentPink,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _activeAds.length,
        itemBuilder: (context, index) {
          final ad = _activeAds[index];
          return _buildAdCard(ad);
        },
      ),
    );
  }

  Widget _buildAdCard(dynamic ad) {
    String dateRange = "Đang diễn ra";
    try {
      if (ad['startUtc'] != null && ad['endUtc'] != null) {
        final start = DateTime.parse(ad['startUtc']).toLocal();
        final end = DateTime.parse(ad['endUtc']).toLocal();
        final fmt = DateFormat('dd/MM');
        dateRange = "${fmt.format(start)} - ${fmt.format(end)}";
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: CrystalTheme.accentPink.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      // [THÊM] Material & InkWell để tạo hiệu ứng bấm và gọi hàm
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _onAdTap(ad), // Gọi hàm xử lý click Ad
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  ad['bannerImageUrl'] ?? '',
                  height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_,__,___) => Container(height: 160, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: CrystalTheme.accentPink.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(dateRange, style: const TextStyle(color: CrystalTheme.accentPink, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(ad['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(ad['description'] ?? '', style: const TextStyle(color: Colors.grey, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(title, style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold, color: CrystalTheme.textDark)),
    ]);
  }
}