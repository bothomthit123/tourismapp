import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:tourismapp/screens/account_page.dart';
import 'package:tourismapp/screens/home_page.dart';
import 'package:tourismapp/screens/map_page.dart';
import 'package:tourismapp/screens/place_page.dart';
import 'package:tourismapp/screens/admin_page.dart';
import 'package:tourismapp/Conts/api_config.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';
class MainNavigation extends StatefulWidget {
  final int? accountId;
  final String? authToken;

  const MainNavigation({super.key, this.accountId, this.authToken});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0; // Mặc định vào Home_page
  bool _loadingProfile = true;

  // Trạng thái Role
  bool _isSupplier = false;
  bool _isAdmin = false;

  List<Widget> _pages = [];
  List<BottomNavigationBarItem> _navItems = [];

  @override
  void initState() {
    super.initState();
    _buildDefaultPages();
    _loadProfileIfNeeded();
  }

  // --- [MỚI] HÀM HIỂN THỊ HỘP THOẠI XÁC NHẬN THOÁT ---
  Future<bool?> _showExitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận thoát', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc chắn muốn thoát ứng dụng không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Thoát', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  // ---------------------------------------------------

  // Cấu hình mặc định cho User thường
  void _buildDefaultPages() {
    _pages = [
      HomePage(accountId: widget.accountId, key: const PageStorageKey('home')),
      MapPage(accountId: widget.accountId, authToken: widget.authToken, key: const PageStorageKey('map')),
      AccountPage(accountId: widget.accountId, authToken: widget.authToken),
    ];
    _navItems = const [
      BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Trang chủ'),
      BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map_rounded), label: 'Bản đồ'),
      BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person_rounded), label: 'Tài khoản'),
    ];
  }

  // Hàm dựng giao diện theo Role
  void _buildPagesForRole() {
    // TRƯỜNG HỢP 1: ADMIN
    if (_isAdmin) {
      _pages = [
        HomePage(accountId: widget.accountId, key: const PageStorageKey('home')),
        MapPage(accountId: widget.accountId, authToken: widget.authToken, key: const PageStorageKey('map')),
        AdminPage(authToken: widget.authToken ?? ""),
        AccountPage(accountId: widget.accountId, authToken: widget.authToken),
      ];
      _navItems = const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Trang chủ'),
        BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map_rounded), label: 'Bản đồ'),
        BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), activeIcon: Icon(Icons.admin_panel_settings), label: 'Quản trị'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person_rounded), label: 'Tài khoản'),
      ];
    }
    // TRƯỜNG HỢP 2: SUPPLIER
    else if (_isSupplier) {
      _pages = [
        HomePage(accountId: widget.accountId, key: const PageStorageKey('home')),
        MapPage(accountId: widget.accountId, authToken: widget.authToken, key: const PageStorageKey('map')),
        PlacePage(accountId: widget.accountId!, authToken: widget.authToken),
        AccountPage(accountId: widget.accountId, authToken: widget.authToken),
      ];
      _navItems = const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Trang chủ'),
        BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map_rounded), label: 'Bản đồ'),
        BottomNavigationBarItem(icon: Icon(Icons.business_center_outlined), activeIcon: Icon(Icons.business_center_rounded), label: 'Quản lý'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person_rounded), label: 'Tài khoản'),
      ];
    }
    // TRƯỜNG HỢP 3: USER THƯỜNG
    else {
      _buildDefaultPages();
    }

    if (_selectedIndex >= _pages.length) _selectedIndex = 0;
  }

  Future<void> _loadProfileIfNeeded() async {
    final token = widget.authToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loadingProfile = false;
        _isSupplier = false;
        _isAdmin = false;
        _buildPagesForRole();
      });
      return;
    }
    try {
      final uri = Uri.parse('$baseUrl/me/profile');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final json = jsonDecode(resp.body);
        Map<String, dynamic>? data;
        if (json is Map && json['data'] is Map) {
          data = Map<String, dynamic>.from(json['data'] as Map);
        } else if (json is Map) {
          data = Map<String, dynamic>.from(json);
        }
        final roleRaw = data?['role']?.toString().toLowerCase() ?? '';
        setState(() {
          _isAdmin = roleRaw == 'admin';
          _isSupplier = roleRaw == 'supplier';
        });
      } else {
        setState(() {
          _isSupplier = false;
          _isAdmin = false;
        });
      }
    } catch (e) {
      debugPrint(">>>> LỖI TẢI PROFILE: $e");
      setState(() {
        _isSupplier = false;
        _isAdmin = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _buildPagesForRole();
        });
      }
    }
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final primaryBlue = Theme.of(context).primaryColor;
    const selectedBlue =  CrystalTheme.primaryBlue;

    // ---  BỌC POPSCOPE BÊN NGOÀI SCAFFOLD ---
    return PopScope(
      canPop: false, // Ngăn chặn back mặc định
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }

        // Nếu đã ở tab đầu tiên (Trang chủ), hiện xác nhận thoát app
        final bool shouldExit = await _showExitDialog(context) ?? false;
        if (shouldExit) {
          SystemNavigator.pop(); // Thoát hẳn ứng dụng (thu nhỏ app)
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: _pages),

        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: primaryBlue.withOpacity(0.25),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 0,

              selectedItemColor: selectedBlue,
              unselectedItemColor: Colors.blueGrey[200],

              currentIndex: _selectedIndex,
              onTap: _onItemTapped,

              showUnselectedLabels: true,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),

              items: _navItems,
            ),
          ),
        ),
      ),
    );
  }
}