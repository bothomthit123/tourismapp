// Cái này để cấu hình overpass truy cập API của bên thứ 3
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
class OverpassService {
  // Chuyển sang máy chủ mirror (lz4) của Overpass để tránh bị chặn IP
  // Nếu lz4 vẫn lỗi đổi thành: 'https://overpass.kumi.systems/api/interpreter'
  static const _endpoint = 'https://lz4.overpass-api.de/api/interpreter';

  Future<Map<String, dynamic>> search(String finalQuery) async {
    final uri = Uri.parse(_endpoint);

    //  Ngụy trang tránh bị chặn
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    // Truyền lại bằng Map để Dart tự động handle việc URL-encode một cách an toàn nhất
    final response = await http.post(
      uri,
      headers: headers, // Sử dụng biến headers đã định nghĩa ở trên
      body: { 'data': finalQuery },
    );

    debugPrint('[OSM] POST $uri -> ${response.statusCode}');

//  SOI DỮ LIỆU THÔ
    if (response.statusCode == 200) {
      developer.log(
        'DỮ LIỆU THÔ TỪ OVERPASS:',
        name: 'OSM_DEBUG',
        error: response.body, // In toàn bộ body vào vùng error để highlight màu
      );

      final decoded = jsonDecode(response.body);
      final elements = decoded['elements'] as List?;

      debugPrint('[OSM] Số lượng địa điểm tìm thấy: ${elements?.length ?? 0}');

      return (decoded);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}