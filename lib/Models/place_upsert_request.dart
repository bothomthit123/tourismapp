import 'fsq_place.dart';

class PlaceUpsertRequest {
  final String fsqId;
  final String name;
  final String address;
  final String category;
  final double latitude;
  final double longitude;

  PlaceUpsertRequest({
    required this.fsqId,
    required this.name,
    required this.address,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceUpsertRequest.fromFsq(FsqPlace p) => PlaceUpsertRequest(
    fsqId: p.fsqId,
    name: p.name,
    address: p.address,
    category: p.category,
    latitude: p.lat,
    longitude: p.lng,
  );

  Map<String, dynamic> toJson() => {
    'fsqId': fsqId,
    'name': name,
    'address': address,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
  };
}
