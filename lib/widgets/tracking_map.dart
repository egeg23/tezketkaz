import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../theme/app_theme.dart';

/// Map for live order tracking. Renders shop / customer / courier pins, an
/// optional polyline along the active leg of the route, and (Phase 2)
/// optional delivery-zone polygons.
///
/// Backwards-compat: callers from Phase 0/1 still use
/// `TrackingMap(shopPoint:, customerPoint:, courierPoint?, phase:)`. The new
/// `zonePolygon` and `extraPolylines` parameters are opt-in.
class TrackingMap extends StatefulWidget {
  /// Shop pin (red).
  final Point shopPoint;

  /// Customer pin (blue).
  final Point customerPoint;

  /// Courier pin (green) — animated when location updates via socket.
  final Point? courierPoint;

  /// Highlights which leg of the trip is active.
  final TrackingPhase phase;

  /// Optional delivery zone polygon (semi-transparent overlay). When `null`
  /// no polygon is drawn.
  final List<Point>? zonePolygon;

  /// Optional extra polylines (e.g. courier → shop, shop → customer) drawn
  /// in addition to the default route line.
  final List<List<Point>> extraPolylines;

  const TrackingMap({
    super.key,
    required this.shopPoint,
    required this.customerPoint,
    this.courierPoint,
    this.phase = TrackingPhase.toShop,
    this.zonePolygon,
    this.extraPolylines = const [],
  });

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

enum TrackingPhase { toShop, toCustomer }

class _TrackingMapState extends State<TrackingMap> {
  YandexMapController? _controller;
  bool _hasApiKey = true; // Установится false если init упадёт

  @override
  void didUpdateWidget(covariant TrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-frame when the courier pin moves (animated effect via map camera).
    if (oldWidget.courierPoint != widget.courierPoint && _controller != null) {
      _frameRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasApiKey) return _Placeholder(phase: widget.phase);

    try {
      return YandexMap(
        onMapCreated: (controller) async {
          _controller = controller;
          await _frameRoute();
        },
        mapObjects: _buildObjects(),
      );
    } catch (_) {
      return _Placeholder(phase: widget.phase);
    }
  }

  List<MapObject> _buildObjects() {
    final objects = <MapObject>[];

    // Optional delivery zone polygon (drawn first so pins sit above it).
    final zone = widget.zonePolygon;
    if (zone != null && zone.length >= 3) {
      objects.add(PolygonMapObject(
        mapId: const MapObjectId('zone'),
        polygon: Polygon(
          outerRing: LinearRing(points: zone),
          innerRings: const [],
        ),
        strokeColor: AppColors.primary,
        strokeWidth: 2,
        fillColor: AppColors.primary.withValues(alpha: 0.12),
      ));
    }

    // Shop pin — red brand colour.
    objects.add(PlacemarkMapObject(
      mapId: const MapObjectId('shop'),
      point: widget.shopPoint,
      icon: PlacemarkIcon.single(PlacemarkIconStyle(
        image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.error)),
        scale: 1.5,
      )),
    ));

    // Customer pin — blue.
    objects.add(PlacemarkMapObject(
      mapId: const MapObjectId('customer'),
      point: widget.customerPoint,
      icon: PlacemarkIcon.single(PlacemarkIconStyle(
        image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.info)),
        scale: 1.5,
      )),
    ));

    // Courier pin — green, larger.
    if (widget.courierPoint != null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('courier'),
        point: widget.courierPoint!,
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.success)),
          scale: 2.0,
        )),
      ));
    }

    // Default active-leg polyline.
    final routePoints = widget.phase == TrackingPhase.toShop
      ? [widget.courierPoint ?? widget.shopPoint, widget.shopPoint]
      : [widget.shopPoint, widget.customerPoint];

    objects.add(PolylineMapObject(
      mapId: const MapObjectId('route'),
      polyline: Polyline(points: routePoints),
      strokeColor: AppColors.primary,
      strokeWidth: 4,
    ));

    // Extra polylines (courier↔shop, shop↔customer, etc).
    for (var i = 0; i < widget.extraPolylines.length; i++) {
      final pts = widget.extraPolylines[i];
      if (pts.length < 2) continue;
      objects.add(PolylineMapObject(
        mapId: MapObjectId('route_extra_$i'),
        polyline: Polyline(points: pts),
        strokeColor: AppColors.primary.withValues(alpha: 0.5),
        strokeWidth: 3,
      ));
    }

    return objects;
  }

  Future<void> _frameRoute() async {
    if (_controller == null) return;
    final points = <Point>[widget.shopPoint, widget.customerPoint];
    if (widget.courierPoint != null) points.add(widget.courierPoint!);
    if (widget.zonePolygon != null) points.addAll(widget.zonePolygon!);

    final lats = points.map((p) => p.latitude).toList()..sort();
    final lngs = points.map((p) => p.longitude).toList()..sort();

    await _controller!.moveCamera(
      CameraUpdate.newBounds(BoundingBox(
        southWest: Point(latitude: lats.first - 0.005, longitude: lngs.first - 0.005),
        northEast: Point(latitude: lats.last + 0.005, longitude: lngs.last + 0.005),
      )),
      animation: const MapAnimation(duration: 0.5),
    );
  }

  Uint8List _pinBytes(Color color) {
    // Placeholder bytes — Yandex MapKit needs an icon image, but the upstream
    // build hasn't shipped real raster pins yet. Returning a single byte keeps
    // the existing behaviour from Phase 0; production will swap this for
    // proper PNGs.
    return Uint8List.fromList([0]);
  }
}

class _Placeholder extends StatelessWidget {
  final TrackingPhase phase;
  const _Placeholder({required this.phase});

  @override
  Widget build(BuildContext context) {
    final isToShop = phase == TrackingPhase.toShop;
    return Container(
      color: isToShop ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isToShop ? '🏪' : '🏠', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            const Text('Yandex MapKit',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              'API kalitini AndroidManifest va Info.plist da\nko\'rsating',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
