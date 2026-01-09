import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:tourismapp/Conts/api_config.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';

class AdminPage extends StatefulWidget {
  final String authToken;
  const AdminPage({super.key, required this.authToken});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  // --- HELPERS ---
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.authToken}',
  };

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : CrystalTheme.primaryBlue,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Dashboard", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          centerTitle: true,
          flexibleSpace: Container(decoration: BoxDecoration(gradient: CrystalTheme.blueGradient)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.people), text: "Tài khoản"),
              Tab(icon: Icon(Icons.ad_units), text: "Quảng cáo"),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE1F5FE), Colors.white]),
          ),
          child: const TabBarView(
            children: [
              _AccountManagerTab(), // Tab 1: Quản lý User
              _AdsManagerTab(),     // Tab 2: Quản lý Ads
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
// TAB 1: QUẢN LÝ TÀI KHOẢN
// =========================================================
class _AccountManagerTab extends StatefulWidget {
  const _AccountManagerTab();

  @override
  State<_AccountManagerTab> createState() => _AccountManagerTabState();
}

class _AccountManagerTabState extends State<_AccountManagerTab> {
  bool _loading = true;
  List<dynamic> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    // Lấy token từ widget cha (AdminPage).
    // Lưu ý: Trong thực tế bạn nên dùng Provider/GetX để lấy token toàn cục.
    // Ở đây mình giả định context.findAncestorWidgetOfExactType sẽ hoạt động hoặc bạn truyền token xuống.
    // Cách fix nhanh nhất: Truyền token vào constructor của Tab này.
    // Tuy nhiên để đơn giản code demo, mình sẽ lấy từ state cha thông qua context (cần setup Provider).
    // => Giải pháp đơn giản cho code này: Gọi API từ Parent hoặc pass param.
    // Để code chạy được ngay, mình sẽ giả sử bạn đã setup biến global token hoặc truyền vào.

    // SỬA: Để đơn giản, mình sẽ truy cập widget cha thông qua context (Yêu cầu AdminPage phải pass token xuống).
    // Ở đây mình sẽ dùng cách tìm State cha (Bad practice nhưng nhanh cho demo)
    final parent = context.findAncestorStateOfType<_AdminPageState>();
    if (parent == null) return;

    try {
      final resp = await http.get(Uri.parse('$baseUrl/api/admin/accounts'), headers: parent._headers);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        setState(() => _accounts = json['data']);
      }
    } catch (e) {
      debugPrint("Lỗi load accounts: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLock(int id, int index) async {
    final parent = context.findAncestorStateOfType<_AdminPageState>();
    if (parent == null) return;

    try {
      final resp = await http.post(Uri.parse('$baseUrl/api/admin/accounts/$id/toggle-lock'), headers: parent._headers);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        setState(() {
          _accounts[index]['isLocked'] = json['isLocked'];
        });
        parent._toast(json['isLocked'] ? "Đã khóa tài khoản" : "Đã mở khóa");
      } else {
        parent._toast("Lỗi: ${resp.statusCode}", isError: true);
      }
    } catch (e) {
      parent._toast("Lỗi kết nối", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_accounts.isEmpty) return const Center(child: Text("Không có tài khoản nào"));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _accounts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final acc = _accounts[i];
        final isLocked = acc['isLocked'] == true;
        final isSupplier = acc['role'] == "Supplier";

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSupplier ? Colors.orange.shade100 : Colors.blue.shade100,
              child: Icon(isSupplier ? Icons.store : Icons.person, color: isSupplier ? Colors.orange : Colors.blue),
            ),
            title: Text(acc['name'] ?? "No Name", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(acc['email']),
                Text(acc['role'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            trailing: acc['role'] == 'Admin'
                ? const Chip(label: Text("Admin", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                : IconButton(
              icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? Colors.red : Colors.green),
              tooltip: isLocked ? "Mở khóa" : "Khóa tài khoản",
              onPressed: () => _toggleLock(acc['accountId'], i),
            ),
          ),
        );
      },
    );
  }
}

// =========================================================
// TAB 2: QUẢN LÝ QUẢNG CÁO
// =========================================================
class _AdsManagerTab extends StatefulWidget {
  const _AdsManagerTab();

  @override
  State<_AdsManagerTab> createState() => _AdsManagerTabState();
}

class _AdsManagerTabState extends State<_AdsManagerTab> {
  bool _loading = true;
  List<dynamic> _ads = [];

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds() async {
    setState(() => _loading = true);
    final parent = context.findAncestorStateOfType<_AdminPageState>();
    if (parent == null) return;

    try {
      final resp = await http.get(Uri.parse('$baseUrl/api/admin/advertisements/all'), headers: parent._headers);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        setState(() => _ads = json['data']);
      }
    } catch (e) {
      debugPrint("Lỗi load ads: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAd(int id) async {
    final parent = context.findAncestorStateOfType<_AdminPageState>();
    if (parent == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xóa quảng cáo?"),
        content: const Text("Hành động này không thể hoàn tác."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Xóa")),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final resp = await http.delete(Uri.parse('$baseUrl/api/advertisements/$id'), headers: parent._headers);
      if (resp.statusCode == 204 || resp.statusCode == 200) {
        setState(() => _ads.removeWhere((a) => a['adId'] == id));
        parent._toast("Đã xóa quảng cáo");
      } else {
        parent._toast("Lỗi xóa: ${resp.statusCode}", isError: true);
      }
    } catch (e) {
      parent._toast("Lỗi kết nối", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_ads.isEmpty) return const Center(child: Text("Không có quảng cáo nào"));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final ad = _ads[i];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              if (ad['bannerImageUrl'] != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.network(
                    ad['bannerImageUrl'],
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_,__,___) => const SizedBox(height: 50, child: Icon(Icons.broken_image)),
                  ),
                ),
              ListTile(
                title: Text(ad['title'] ?? "No Title", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Quán: ${ad['supplierName']}\nHết hạn: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(ad['endUtc']).toLocal())}"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteAd(ad['adId']),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}