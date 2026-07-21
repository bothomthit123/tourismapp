import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import để chỉnh thanh trạng thái
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart'; // Thư viện caching
import 'package:provider/provider.dart';
import 'package:tourismapp/Models/download_config_provider.dart';
import 'package:tourismapp/Models/download_provider.dart';
import 'package:tourismapp/Models/region_selector_provider.dart';
import 'package:tourismapp/Conts/crystal_theme.dart';
import 'package:flutter/foundation.dart';
import 'Screens/main_navigation.dart';
// import 'screens/login_page.dart';

// --- CẤU HÌNH CACHE TRUNG TÂM  ---
const String kMainMapStoreName = 'tourismMapStore';
const String kBrowsingCacheStoreName = 'browsingCacheStore';
const String kMapUrlKey = 'urlTemplate';
const String kMapUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
// ----------------------------------
// =======================================================
// 2. MAIN FUNCTION
// =======================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //  Đặt thanh trạng thái trong suốt để UI tràn lên trên
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Kiểm tra: Nếu KHÔNG PHẢI LÀ WEB (!kIsWeb) thì mới chạy logic caching
  if (!kIsWeb) {
    try {
      // 1. Khởi tạo Backend
      await FMTCObjectBoxBackend().initialise();
      debugPrint("Khởi tạo Caching Backend thành công!");

      // 2. Cấu hình Kho 1 (Chính)
      final mainStore = FMTCStore(kMainMapStoreName);
      if (!(await mainStore.manage.ready)) {
        await mainStore.manage.create();
        debugPrint("Đã tạo store chính '$kMainMapStoreName'!");
      }
      await mainStore.metadata.set(key: kMapUrlKey, value: kMapUrlTemplate);

      // 3. Cấu hình Kho 2 (Cache tự động)
      final cacheStore = FMTCStore(kBrowsingCacheStoreName);
      if (!(await cacheStore.manage.ready)) {
        await cacheStore.manage.create();
        debugPrint("Đã tạo store cache '$kBrowsingCacheStoreName'!");
      }
      await cacheStore.metadata.set(key: kMapUrlKey, value: kMapUrlTemplate);

      // 4. Giới hạn dung lượng
      await cacheStore.manage.setMaxLength(5000);
      debugPrint("Đã giới hạn dung lượng kho cache.");

      // Dọn dẹp cache cũ
      final expiryDate = DateTime.now().subtract(const Duration(days: 60));
      await cacheStore.manage.removeTilesOlderThan(expiry: expiryDate);
      debugPrint("Đã dọn dẹp cache (cũ hơn 60 ngày) thành công.");

    } catch (e) {
      debugPrint("Lỗi khởi tạo Caching (Mobile): $e");
    }
  } else {
    debugPrint("Đang chạy trên Web: Đã bỏ qua khởi tạo FMTC (Caching Offline)");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DownloadConfigurationProvider()),
        ChangeNotifierProvider(create: (_) => DownloadingProvider()),
        ChangeNotifierProvider(create: (_) => RegionSelectionProvider()),
      ],
      child: const TourismApp(),
    ),
  );
}

class TourismApp extends StatelessWidget {
  const TourismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tourism App',

      theme: CrystalTheme.themeData,
      debugShowCheckedModeBanner: false,
      home: const MainNavigation(
        accountId: null,
        authToken: null,
      ),
    );
  }
}