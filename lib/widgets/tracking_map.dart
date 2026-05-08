import 'dart:typed_data';
import 'dart:ui' as ui;
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

  // Phase 6 — cached raster pin bytes. Generating PNGs synchronously inside
  // build() is not allowed (requires async) and would re-rasterize on every
  // rebuild, so we render once in initState and cache.
  Uint8List? _shopPin;
  Uint8List? _customerPin;
  Uint8List? _courierPin;

  @override
  void initState() {
    super.initState();
    _bakePins();
  }

  Future<void> _bakePins() async {
    final shop = await _pinBytes(AppColors.error);
    final customer = await _pinBytes(AppColors.info);
    final courier = await _pinBytes(AppColors.success);
    if (!mounted) return;
    setState(() {
      _shopPin = shop;
      _customerPin = customer;
      _courierPin = courier;
    });
  }

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
    // Wait for the pins to be baked before drawing the map. Showing the
    // placeholder briefly is harmless — `_bakePins` finishes in well under a
    // frame on real devices.
    if (_shopPin == null || _customerPin == null || _courierPin == null) {
      return _Placeholder(phase: widget.phase);
    }

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
        image: BitmapDescriptor.fromBytes(_shopPin!),
        scale: 1.5,
      )),
    ));

    // Customer pin — blue.
    objects.add(PlacemarkMapObject(
      mapId: const MapObjectId('customer'),
      point: widget.customerPoint,
      icon: PlacemarkIcon.single(PlacemarkIconStyle(
        image: BitmapDescriptor.fromBytes(_customerPin!),
        scale: 1.5,
      )),
    ));

    // Courier pin — green, larger.
    if (widget.courierPoint != null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('courier'),
        point: widget.courierPoint!,
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: BitmapDescriptor.fromBytes(_courierPin!),
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

  /// Phase 6 — generate a 96x96 raster pin (white outer ring + filled core)
  /// at runtime so we don't need to ship binary asset files. Result is the
  /// PNG bytes that [BitmapDescriptor.fromBytes] expects.
  Future<Uint8List> _pinBytes(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 96.0;
    const center = Offset(size / 2, size / 2);
    // Outer ring (white).
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
    // Filled core.
    canvas.drawCircle(center, size / 2 - 8, Paint()..color = color);
    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
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
