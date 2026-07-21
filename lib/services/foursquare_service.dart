// lib/services/foursquare_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class FoursquareService {
  final String apiKey;
  final String apiVersion;

  FoursquareService({
    required this.apiKey,
    this.apiVersion = '2025-06-17',
  });

  static const _endpoint = 'https://places-api.foursquare.com/places/search';

  Future<Map<String, dynamic>> search({
    required String query,
    required LatLng center,
    int limit = 15,
    int radius = 2000,
    String? categories,
  }) async {
    String urlStr = '$_endpoint'
        '?query=${Uri.encodeComponent(query)}'
        '&ll=${center.latitude},${center.longitude}'
        '&limit=$limit'
        '&radius=$radius';

    // Nối chuỗi category nếu có truyền vào
    if (categories != null && categories.isNotEmpty) {
      urlStr += '&categories=$categories';
    }

    final uri = Uri.parse(urlStr);

    final headers = {
      'Authorization': 'Bearer ${apiKey.trim()}',
      'Accept': 'application/json',
      'X-Places-Api-Version': apiVersion,
    };

    final resp = await http.get(uri, headers: headers);
    debugPrint('[FSQ] GET $uri -> ${resp.statusCode}');
    if (resp.statusCode != 200) {
      debugPrint('[FSQ] BODY: ${resp.body}');
      throw Exception('FSQ ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}