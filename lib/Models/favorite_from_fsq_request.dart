import 'fsq_place.dart';

class FavoriteFromFsqRequest {
  final int accountId;
  final String fsqId;
  final String name;
  final String address;
  final String category;
  final double latitude;
  final double longitude;

  FavoriteFromFsqRequest({
    required this.accountId,
    required this.fsqId,
    required this.name,
    required this.address,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  factory FavoriteFromFsqRequest.fromFsq({
    required int accountId,
    required FsqPlace place,
  }) =>
      FavoriteFromFsqRequest(
        accountId: accountId,
        fsqId: place.fsqId,
        name: place.name,
        address: place.address,
        category: place.category,
        latitude: place.lat,
        longitude: place.lng,
      );

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'fsqId': fsqId,
    'name': name,
    'address': address,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
  };
}
