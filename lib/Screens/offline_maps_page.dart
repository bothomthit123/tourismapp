import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:flutter/foundation.dart';
// 1. Import Theme & Config
import 'package:tourismapp/Conts/crystal_theme.dart';
import '../main.dart'; // Import constants
import '../Models/download_config_provider.dart';
import '../Models/download_provider.dart';
import '../Models/region_selector_provider.dart';
import '../services/location_service.dart';

class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  late final MapController _mapController;
  LatLng? _currentGpsLocation;
  bool _isDrawing = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchLoading = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _ensureLocation(moveMap: true);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureLocation({bool moveMap = false}) async {
    final newPos = await LocationService.getUserLocation();
    if (newPos != null && mounted) {
      setState(() => _currentGpsLocation = newPos);
      if (moveMap) {
        _mapController.move(newPos, 15);
      }
    }
  }

  Future<void> _searchAndMove() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() { _isSearchLoading = true; });

    try {
      final locations = await geocoding.locationFromAddress(query);
      if (locations.isNotEmpty && mounted) {
        final loc = locations.first;
        final latLng = LatLng(loc.latitude, loc.longitude);
        _mapController.move(latLng, 15);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy địa chỉ')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tìm kiếm: $e')));
    }
    setState(() { _isSearchLoading = false; });
  }

  void _toggleDrawingMode() {
    context.read<RegionSelectionProvider>().clearCoordinates();
    setState(() { _isDrawing = !_isDrawing; });
  }
  void _undoLastPoint() => context.read<RegionSelectionProvider>().removeLastCoordinate();
  void _clearCurrentDrawing() => context.read<RegionSelectionProvider>().clearCoordinates();

  void _commitPolygon() {
    final provider = context.read<RegionSelectionProvider>();
    final points = provider.currentConstructingCoordinates;
    if (points.length < 3) return;
    provider.addConstructedRegion(CustomPolygonRegion(points));
    setState(() { _isDrawing = false; });
  }

  void _clearAllRegions() {
    context.read<RegionSelectionProvider>().clearConstructedRegions();
    context.read<RegionSelectionProvider>().clearCoordinates();
  }

  @override
  Widget build(BuildContext context) {
    final downloadingProvider = context.watch<DownloadingProvider>();
    final regionProvider = context.watch<RegionSelectionProvider>();
    final selectedRegions = regionProvider.constructedRegions;
    final currentDrawingPoints = regionProvider.currentConstructingCoordinates;

    return Scaffold(
      // [THEME] AppBar Gradient
      appBar: AppBar(
        title: Text(_isDrawing ? "Đang vẽ vùng..." : "Tải bản đồ Offline", style: const TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: CrystalTheme.blueGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Vị trí của tôi',
            onPressed: () => _ensureLocation(moveMap: true),
          ),
          if (_isDrawing)
            IconButton(icon: const Icon(Icons.check), tooltip: 'Hoàn tất', onPressed: _commitPolygon),
          if (_isDrawing && currentDrawingPoints.isNotEmpty) ...[
            IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: _undoLastPoint),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Xóa nét', onPressed: _clearCurrentDrawing),
          ],
          IconButton(
            icon: Icon(_isDrawing ? Icons.close : Icons.edit, color: _isDrawing ? Colors.white : null),
            tooltip: _isDrawing ? 'Hủy' : 'Vẽ vùng',
            onPressed: _toggleDrawingMode,
          ),
          if (selectedRegions.isNotEmpty || currentDrawingPoints.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep), tooltip: 'Xóa tất cả', onPressed: _clearAllRegions),
        ],
      ),
      body: Column(
        children: [
          // [THEME] Search Bar Style
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchAndMove(),
                decoration: InputDecoration(
                  hintText: 'Tìm địa chỉ (ví dụ: Quận 1)...',
                  hintStyle: TextStyle(color: Colors.blueGrey[300]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  suffixIcon: _isSearchLoading
                      ? Padding(padding: const EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2, color: CrystalTheme.primaryBlue))
                      : IconButton(icon: Icon(Icons.search, color: CrystalTheme.primaryBlue), onPressed: _searchAndMove),
                ),
              ),
            ),
          ),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentGpsLocation ?? const LatLng(10.776889, 106.700806),
                initialZoom: 13,
                onTap: (_, latlng) {
                  if (_isDrawing) context.read<RegionSelectionProvider>().addCoordinate(latlng);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: kMapUrlTemplate,
                  userAgentPackageName: 'com.example.tourismapp',

                  tileProvider: kIsWeb
                      ? NetworkTileProvider()
                      : FMTCTileProvider(
                    stores: {
                      kMainMapStoreName: BrowseStoreStrategy.read,
                      kBrowsingCacheStoreName: BrowseStoreStrategy.read,
                    },
                  ),
                ),

                // [THEME] Vùng đã chọn (Màu xanh pha lê)
                PolygonLayer(
                  polygons: selectedRegions.keys.whereType<CustomPolygonRegion>().map((p) => Polygon(
                    points: p.outline,
                    color: CrystalTheme.primaryBlue.withOpacity(0.3),
                    borderColor: CrystalTheme.primaryBlue,
                    borderStrokeWidth: 2,
                    isFilled: true,
                  )).toList(),
                ),

                // [THEME] Nét vẽ hiện tại (Màu hồng phấn để phân biệt)
                if (_isDrawing && currentDrawingPoints.isNotEmpty)
                  PolygonLayer(polygons: [Polygon(
                    points: currentDrawingPoints,
                    color: CrystalTheme.accentPink.withOpacity(0.3),
                    borderColor: CrystalTheme.accentPink,
                    borderStrokeWidth: 2,
                    isFilled: true,
                  )]),

                MarkerLayer(markers: [
                  ...currentDrawingPoints.map((p) => Marker(width: 8, height: 8, point: p, child: Container(decoration: BoxDecoration(color: CrystalTheme.accentPink, shape: BoxShape.circle)))).toList(),
                  if (_currentGpsLocation != null)
                    Marker(point: _currentGpsLocation!, width: 24, height: 24, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, color: CrystalTheme.primaryBlue.withOpacity(0.2)), child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: CrystalTheme.primaryBlue, border: Border.all(color: Colors.white, width: 2))))),
                ]),
              ],
            ),
          ),

          if (downloadingProvider.isFocused)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: downloadingProvider.latestDownloadProgress.percentageProgress / 100,
                    color: CrystalTheme.primaryBlue,
                    backgroundColor: CrystalTheme.lightBlueBg,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${downloadingProvider.latestDownloadProgress.percentageProgress.toStringAsFixed(1)} % - Đã tải: ${downloadingProvider.latestDownloadProgress.successfulTilesCount} / ${downloadingProvider.latestDownloadProgress.maxTilesCount}',
                    style: TextStyle(color: CrystalTheme.textDark, fontSize: 12),
                  ),
                ],
              ),
            ),

          // [THEME] Download Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                  gradient: CrystalTheme.blueGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: CrystalTheme.primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text("Bắt đầu tải vùng đã chọn", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: _isDrawing || selectedRegions.isEmpty ? null : _startDownload,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload() async {
    final downloadConfig = context.read<DownloadConfigurationProvider>();
    final regionProvider = context.read<RegionSelectionProvider>();
    final downloadingProvider = context.read<DownloadingProvider>();

    final store = FMTCStore(kMainMapStoreName);
    final allMetadata = await store.metadata.read;
    final urlTemplate = allMetadata[kMapUrlKey];

    if (urlTemplate == null || urlTemplate.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi URL bản đồ'), backgroundColor: Colors.red));
      return;
    }

    final downloadableRegion = MultiRegion(regionProvider.constructedRegions.keys.toList()).toDownloadable(
      minZoom: downloadConfig.minZoom, maxZoom: downloadConfig.maxZoom, start: downloadConfig.startTile, end: downloadConfig.endTile,
      options: TileLayer(urlTemplate: urlTemplate, userAgentPackageName: 'com.example.tourismapp'),
    );

    final downloadStreams = store.download.startForeground(
      region: downloadableRegion, parallelThreads: downloadConfig.parallelThreads, maxBufferLength: downloadConfig.maxBufferLength,
      skipExistingTiles: downloadConfig.skipExistingTiles, skipSeaTiles: downloadConfig.skipSeaTiles, retryFailedRequestTiles: downloadConfig.retryFailedRequestTiles, rateLimit: downloadConfig.rateLimit,
    );

    await downloadingProvider.assignDownload(storeName: kMainMapStoreName, downloadableRegion: downloadableRegion, downloadStreams: downloadStreams);
  }
}