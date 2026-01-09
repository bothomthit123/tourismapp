import 'api_client.dart';
import 'package:tourismapp/models/place_upsert_request.dart';
import 'package:tourismapp/models/favorite_from_fsq_request.dart';

class PlaceService {
  final ApiClient _api;

  PlaceService(this._api);

  /// Upsert Place từ Foursquare vào DB, trả về { placeId, source: 'foursquare' }
  Future<Map<String, dynamic>> upsertFromFsq(PlaceUpsertRequest req) async {
    return _api.postJson('/api/places/from-fsq', req.toJson());
  }

  /// Upsert Place + tạo Favorite cho account
  Future<Map<String, dynamic>> favoriteFromFsq(FavoriteFromFsqRequest req) async {
    return _api.postJson('/api/favorites/from-fsq', req.toJson());
  }
}
