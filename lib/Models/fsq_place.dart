class FsqPlace {
  final String fsqId;
  final String name;
  final String address;
  final String category;
  final double lat;
  final double lng;

  FsqPlace({
    required this.fsqId,
    required this.name,
    required this.address,
    required this.category,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
    'fsqId': fsqId,
    'name': name,
    'address': address,
    'category': category,
    'latitude': lat,
    'longitude': lng,
  };
}
