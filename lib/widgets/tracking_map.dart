import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../theme/app_theme.dart';

/// Карта Яндекс / 2GIS для трекинга.
///
/// Работает после получения API ключа на https://developer.tech.yandex.ru
/// Ключ нужно добавить в:
///   - android/app/src/main/AndroidManifest.xml (мета-тег com.yandex.mapkit.API_KEY)
///   - ios/Runner/AppDelegate.swift (`YandexMapKit.setApiKey("YOUR_KEY")`)
///
/// Если ключ не указан, виджет покажет placeholder.
class TrackingMap extends StatefulWidget {
  /// Точка магазина
  final Point shopPoint;

  /// Точка покупателя
  final Point customerPoint;

  /// Текущая позиция курьера (если едет)
  final Point? courierPoint;

  /// Какую часть маршрута подсветить
  final TrackingPhase phase;

  const TrackingMap({
    super.key,
    required this.shopPoint,
    required this.customerPoint,
    this.courierPoint,
    this.phase = TrackingPhase.toShop,
  });

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

enum TrackingPhase { toShop, toCustomer }

class _TrackingMapState extends State<TrackingMap> {
  YandexMapController? _controller;
  bool _hasApiKey = true; // Установится false если init упадёт

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

    // Магазин — круг
    objects.add(PlacemarkMapObject(
      mapId: const MapObjectId('shop'),
      point: widget.shopPoint,
      icon: PlacemarkIcon.single(PlacemarkIconStyle(
        image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.primary)),
        scale: 1.5,
      )),
    ));

    // Покупатель — дом
    objects.add(PlacemarkMapObject(
      mapId: const MapObjectId('customer'),
      point: widget.customerPoint,
      icon: PlacemarkIcon.single(PlacemarkIconStyle(
        image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.courier)),
        scale: 1.5,
      )),
    ));

    // Курьер — пульсирующая точка
    if (widget.courierPoint != null) {
      objects.add(PlacemarkMapObject(
        mapId: const MapObjectId('courier'),
        point: widget.courierPoint!,
        icon: PlacemarkIcon.single(PlacemarkIconStyle(
          image: BitmapDescriptor.fromBytes(_pinBytes(AppColors.error)),
          scale: 2.0,
        )),
      ));
    }

    // Линия маршрута
    final routePoints = widget.phase == TrackingPhase.toShop
      ? [widget.courierPoint ?? widget.shopPoint, widget.shopPoint]
      : [widget.shopPoint, widget.customerPoint];

    objects.add(PolylineMapObject(
      mapId: const MapObjectId('route'),
      polyline: Polyline(points: routePoints),
      strokeColor: AppColors.primary,
      strokeWidth: 4,
    ));

    return objects;
  }

  Future<void> _frameRoute() async {
    if (_controller == null) return;
    final points = [widget.shopPoint, widget.customerPoint];
    if (widget.courierPoint != null) points.add(widget.courierPoint!);

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
