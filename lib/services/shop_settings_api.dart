import 'api_client.dart';

/// Phase 6 — shop working-hours editor API.
///
/// Backed by:
///   GET  /api/shops/:shopId/working-hours  → list of 7 rows
///   PUT  /api/shops/:shopId/working-hours  → body: list of 7 rows
class ShopSettingsApi {
  ShopSettingsApi._();
  static final ShopSettingsApi instance = ShopSettingsApi._();

  final _api = ApiClient.instance;

  Future<List<ShopWorkingHoursRow>> getWorkingHours(String shopId) async {
    final res = await _api.get('/api/shops/$shopId/working-hours');
    final raw = res.data;
    final list = (raw is Map ? raw['rows'] ?? raw['workingHours'] ?? raw['data'] : raw) ?? raw;
    final rows = list is List ? list : const [];
    return rows
        .map((r) => ShopWorkingHoursRow.fromJson(
              r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{},
            ))
        .toList();
  }

  Future<void> putWorkingHours(
    String shopId,
    List<ShopWorkingHoursRow> rows,
  ) async {
    await _api.put('/api/shops/$shopId/working-hours',
        rows.map((r) => r.toJson()).toList());
  }
}

class ShopWorkingHoursRow {
  /// 0 = Sunday … 6 = Saturday (matches `Date.getDay()` semantics).
  final int dayOfWeek;
  final String startsAt; // "HH:MM"
  final String endsAt;
  final bool isClosed;

  const ShopWorkingHoursRow({
    required this.dayOfWeek,
    required this.startsAt,
    required this.endsAt,
    required this.isClosed,
  });

  factory ShopWorkingHoursRow.fromJson(Map<String, dynamic> json) {
    return ShopWorkingHoursRow(
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
      startsAt: (json['startsAt'] ?? '09:00').toString(),
      endsAt: (json['endsAt'] ?? '22:00').toString(),
      isClosed: json['isClosed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'startsAt': startsAt,
        'endsAt': endsAt,
        'isClosed': isClosed,
      };

  ShopWorkingHoursRow copyWith({
    int? dayOfWeek,
    String? startsAt,
    String? endsAt,
    bool? isClosed,
  }) =>
      ShopWorkingHoursRow(
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        isClosed: isClosed ?? this.isClosed,
      );
}
