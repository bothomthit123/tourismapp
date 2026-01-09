import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
// Import Theme & Config
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:tourismapp/Conts/api_config.dart';
// Import Screens
import 'login_page.dart';
import 'main_navigation.dart';
import 'trip_page.dart';        // Import trang Chuyến đi
import 'secure_docs_page.dart'; // Import trang Két sắt
class AccountPage extends StatefulWidget {
  final int? accountId;
  final String? authToken;
  const AccountPage({super.key, this.accountId, this.authToken});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // State cho Tab Hồ sơ
  Account? _account;
  List<FavoritePlace> _favorites = [];
  bool _loadingProfile = false;
  String? _errorProfile;
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
    _tabController = TabController(length: 3, vsync: this);
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : CrystalTheme.primaryBlue,
    ));
  }

  // --- LOGIC TAB HỒ SƠ ---
  Future<void> _loadProfileData() async {
    setState(() { _loadingProfile = true; _errorProfile = null; });
    try {
      Account? acc;
      if (_hasToken) {
        acc = await _fetchMeProfile();
      } else if (widget.accountId != null) {
        acc = await _fetchAccount(widget.accountId!);
      } else {
        acc = null;
      }

      final fav = _hasToken ? await _fetchFavorites(page: 1, size: 50) : <FavoritePlace>[];

      if (!mounted) return;
      setState(() {
        _account = acc;
        _favorites = fav;
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorProfile = 'Không thể tải dữ liệu'; _loadingProfile = false; });
    }
  }

  Future<Account?> _fetchMeProfile() async {
    final resp = await http.get(Uri.parse('$baseUrl/me/profile'), headers: _authHeaders(json: false));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final data = (json is Map && json['data'] is Map) ? json['data'] as Map<String, dynamic> : (json is Map ? json as Map<String, dynamic> : null);
      if (data != null) return Account.fromJson(data);
      return null;
    }
    if (resp.statusCode == 401) throw Exception('unauthorized');
    throw Exception('me_profile_${resp.statusCode}');
  }

  Future<Account?> _fetchAccount(int id) async {
    final resp = await http.get(Uri.parse('$baseUrl/api/account/$id'), headers: _authHeaders(json: false));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final data = (json is Map && json['data'] is Map) ? json['data'] as Map<String, dynamic> : null;
      if (data != null) return Account.fromJson(data);
      return null;
    }
    throw Exception('account_${resp.statusCode}');
  }

  Future<List<FavoritePlace>> _fetchFavorites({int page = 1, int size = 20}) async {
    final resp = await http.get(Uri.parse('$baseUrl/me/favorites?page=$page&size=$size'), headers: _authHeaders(json: false));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final data = (json is Map && json['data'] is List) ? json['data'] as List : <dynamic>[];
      return data.map((item) => FavoritePlace.fromJson(item)).toList();
    }
    if (resp.statusCode == 401) throw Exception('unauthorized');
    throw Exception('favorites_${resp.statusCode}');
  }

  Future<void> _logout() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'auth_token');
    await storage.delete(key: 'account_id');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainNavigation(accountId: null, authToken: null)),
          (route) => false,
    );
  }

  Future<void> _unfavoritePlace(FavoritePlace place) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa yêu thích?'),
        content: Text('Bạn có chắc muốn xóa "${place.name}" khỏi danh sách yêu thích?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xóa'), style: FilledButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );

    if (confirmed != true) return;

    final index = _favorites.indexOf(place);
    setState(() { _favorites.remove(place); });

    final url = Uri.parse('$baseUrl/me/favorites/${place.placeId}');
    try {
      final response = await http.delete(url, headers: _authHeaders());
      if (response.statusCode == 200 || response.statusCode == 204) {
        _showToast('Đã xóa khỏi yêu thích', isError: false);
      } else {
        throw Exception('Lỗi ${response.statusCode}');
      }
    } catch (e) {
      _showToast('Lỗi: Không thể xóa. Vui lòng thử lại.', isError: true);
      setState(() { _favorites.insert(index, place); });
    }
  }

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
              // --- HEADER TAB BAR ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]
                ),
                child: Column(
                  children: [
                    Text('Tài khoản', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: CrystalTheme.textDark)),
                    const SizedBox(height: 16),
                    Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                            gradient: CrystalTheme.blueGradient,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey,
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                        dividerColor: Colors.transparent,

                        // Chia đều 3 phần:
                        labelPadding: EdgeInsets.zero, // Xóa padding mặc định để tab co giãn hết cỡ
                        indicatorSize: TabBarIndicatorSize.tab, // Indicator full ô

                        tabs: const [
                          // Bọc trong SizedBox hoặc Container để ép độ rộng nếu cần,
                          // nhưng với labelPadding: zero thì TabBar tự chia đều.
                          Tab(text: "Hồ sơ"),
                          Tab(text: "Chuyến đi"),
                          Tab(text: "Két sắt"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // --- TAB CONTENT ---
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // TAB 1: HỒ SƠ
                    _buildProfileTab(),

                    // TAB 2: CHUYẾN ĐI
                    _hasToken
                        ? TripPage(authToken: widget.authToken)
                        : const Center(child: Text("Vui lòng đăng nhập để xem chuyến đi", style: TextStyle(color: Colors.grey))),

                    // TAB 3: GIẤY TỜ
                    _hasToken
                        ? SecureDocsPage(authToken: widget.authToken)
                        : const Center(child: Text("Vui lòng đăng nhập để truy cập két sắt", style: TextStyle(color: Colors.grey))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget Tab Hồ sơ
  Widget _buildProfileTab() {
    if (_loadingProfile) return const Center(child: CircularProgressIndicator(color: CrystalTheme.primaryBlue));
    if (_errorProfile != null) return _ErrorView(message: _errorProfile!, onRetry: _loadProfileData);

    return RefreshIndicator(
      color: CrystalTheme.primaryBlue,
      onRefresh: _loadProfileData,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_account != null)
            _AccountHeader(data: _account)
          else
            _GuestHeader(onLogin: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()))),

          const SizedBox(height: 24),

          if (_hasToken) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: Colors.redAccent.withOpacity(0.3)), borderRadius: BorderRadius.circular(16), color: Colors.red.withOpacity(0.05)),
              child: TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],

          Row(children: [
            Icon(Icons.favorite_rounded, color: CrystalTheme.accentPink, size: 20),
            const SizedBox(width: 8),
            Text('Địa điểm yêu thích', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: CrystalTheme.textDark)),
            if (!_hasToken) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock_outline, size: 16, color: Colors.grey)),
          ]),
          const SizedBox(height: 12),

          if (!_hasToken)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: const Text('Bạn cần đăng nhập để xem danh sách yêu thích.', style: TextStyle(color: Colors.grey)),
            )
          else if (_favorites.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Chưa có mục yêu thích nào.', style: TextStyle(color: Colors.grey))))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _favorites.length,
              itemBuilder: (context, index) {
                final item = _favorites[index];
                return _FavoriteTile(item: item, onUnfavorite: () => _unfavoritePlace(item));
              },
            ),
        ],
      ),
    );
  }
}

// Gọi các header
class _GuestHeader extends StatelessWidget {
  final VoidCallback onLogin;
  const _GuestHeader({required this.onLogin});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(children: [
        CircleAvatar(radius: 30, backgroundColor: CrystalTheme.lightBlueBg, child: const Icon(Icons.person_off_outlined, size: 30, color: Colors.grey)),
        const SizedBox(height: 12),
        Text('Bạn chưa đăng nhập', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: CrystalTheme.textDark)),
        const SizedBox(height: 4),
        Text('Đăng nhập để trải nghiệm đầy đủ.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey[300])),
        const SizedBox(height: 16),
        Container(width: double.infinity, height: 44, decoration: BoxDecoration(gradient: CrystalTheme.blueGradient, borderRadius: BorderRadius.circular(22)), child: ElevatedButton(onPressed: onLogin, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))), child: const Text('Đăng nhập / Đăng ký', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ]),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final Account? data;
  const _AccountHeader({required this.data});
  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox();
    final name = data!.name.isEmpty ? 'Người dùng' : data!.name;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: CrystalTheme.blueGradient, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const CircleAvatar(radius: 30, backgroundColor: Colors.white, child: Icon(Icons.person, size: 32, color: CrystalTheme.primaryBlue))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)), const SizedBox(height: 4), Text(data!.email, style: const TextStyle(color: Colors.white70, fontSize: 14))])),
      ]),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  final FavoritePlace item;
  final VoidCallback onUnfavorite;
  const _FavoriteTile({required this.item, required this.onUnfavorite});
  @override
  Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: CrystalTheme.lightBlueBg, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.place, color: CrystalTheme.primaryBlue)), title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(item.address ?? '', maxLines: 1), trailing: IconButton(icon: Icon(Icons.favorite, color: CrystalTheme.accentPink), onPressed: onUnfavorite)));
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, style: const TextStyle(color: Colors.red)), const SizedBox(height: 8), FilledButton(onPressed: onRetry, child: const Text('Thử lại'))]));
  }
}

class Account {
  final int accountId; final String name; final String email; final String role; final DateTime? createdAtUtc; final int? supplierId;
  Account({required this.accountId, required this.name, required this.email, required this.role, this.createdAtUtc, this.supplierId});
  factory Account.fromJson(Map<String, dynamic> json) { return Account(accountId: json['accountId'] as int, name: json['name'] as String, email: json['email'] as String, role: json['role'] as String, createdAtUtc: json['createdAtUtc'] != null ? DateTime.tryParse(json['createdAtUtc']) : null, supplierId: json['supplierId'] as int?); }
}

class FavoritePlace {
  final int placeId; final String name; final String? address; final String? category; final dynamic rating; final String source; final double? latitude; final double? longitude;
  FavoritePlace({required this.placeId, required this.name, this.address, this.category, this.rating, required this.source, this.latitude, this.longitude});
  factory FavoritePlace.fromJson(Map<String, dynamic> json) { return FavoritePlace(placeId: json['placeId'] as int, name: json['name'] as String, address: json['address'] as String?, category: json['category'] as String?, rating: json['rating'], source: json['source'] as String? ?? 'unknown', latitude: (json['latitude'] as num?)?.toDouble(), longitude: (json['longitude'] as num?)?.toDouble()); }
}