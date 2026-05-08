import 'api_client.dart';

/// Phase 8.4 — courier-side demand heatmap API client.
///
/// Backed by `GET /api/couriers/heatmap?lat=&lng=&radiusKm=N`. The backend
/// returns:
/// ```
/// { cells: [{lat, lng, count, intensity}, ...], windowMs, radiusKm }
/// ```
/// `intensity` is in `[0, 1]` and is used by the UI to size and shade
/// heatmap circles.
class HeatmapApi {
  HeatmapApi._();
  static final HeatmapApi instance = HeatmapApi._();

  final _api = ApiClient.instance;

  Future<List<HeatmapCell>> me({
    required double lat,
    required double lng,
    double radiusKm = 10,
  }) async {
    final res = await _api.get(
      '/api/couriers/heatmap',
      query: {
        'lat': lat,
        'lng': lng,
        'radiusKm': radiusKm,
      },
    );
    final raw = res.data;
    if (raw is! Map) return const [];
    final cells = raw['cells'];
    if (cells is! List) return const [];
    return cells
        .map((c) => HeatmapCell.fromJson(
              c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{},
            ))
        .where((c) => c.lat != 0 || c.lng != 0)
        .toList();
  }
}

class HeatmapCell {
  final double lat;
  final double lng;
  final int count;
  final double intensity; // 0..1

  const HeatmapCell({
    required this.lat,
    required this.lng,
    required this.count,
    required this.intensity,
  });

  factory HeatmapCell.fromJson(Map<String, dynamic> j) => HeatmapCell(
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        count: _toInt(j['count']),
        intensity: _toDouble(j['intensity']).clamp(0.0, 1.0).toDouble(),
      );
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
