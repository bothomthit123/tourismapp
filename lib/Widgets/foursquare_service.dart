import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class FoursquareService {
  static const _endpoint = 'https://api.foursquare.com/v3/places/search';
  final String apiKey;
  FoursquareService(this.apiKey);

  Future<List<Map<String,dynamic>>> search(String query, LatLng loc) async {
    final url = Uri.parse(
        '$_endpoint?query=${Uri.encodeComponent(query)}&ll=${loc.latitude},${loc.longitude}&limit=10'
    );
    final r = await http.get(url, headers: {
      'Authorization': apiKey.trim(),
      'Accept': 'application/json',
      'User-Agent': 'tourismapp/1.0',
    });
    if (r.statusCode != 200) {
      throw Exception('FSQ ${r.statusCode}: ${r.body}');
    }
    final data = jsonDecode(r.body);
    return List<Map<String,dynamic>>.from(data['results'] ?? []);
  }
}

