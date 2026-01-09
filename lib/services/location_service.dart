import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class LocationService {
  // Biến hàm này thành 'static' để có thể gọi ở bất kỳ đâu
  static Future<LatLng?> getUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: GPS chưa bật');
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('LocationService: Không có quyền vị trí');
        return null;
      }
      final p = await Geolocator.getCurrentPosition();
      return LatLng(p.latitude, p.longitude);
    } catch (e) {
      debugPrint('Lấy vị trí lỗi: $e');
      return null;
    }
  }
}