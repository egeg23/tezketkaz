import 'api_client.dart';

/// Phase 7.3 — promotional banner shown on the home/shops screen.
///
/// Mirrors `GET /api/banners?vertical=&country=`. Title localisation is
/// handled here: `titleFor(localeCode)` falls back uz → ru → en.
class HomeBanner {
  final String id;
  final String? titleUz;
  final String? titleRu;
  final String? titleEn;
  final String? titleKk;
  final String imageUrl;
  final String? deepLink;
  final String? vertical;
  final String? country;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    this.titleUz,
    this.titleRu,
    this.titleEn,
    this.titleKk,
    this.deepLink,
    this.vertical,
    this.country,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> j) => HomeBanner(
        id: j['id'] as String,
        titleUz: j['titleUz'] as String?,
        titleRu: j['titleRu'] as String?,
        titleEn: j['titleEn'] as String?,
        titleKk: j['titleKk'] as String?,
        imageUrl: (j['imageUrl'] as String?) ?? '',
        deepLink: j['deepLink'] as String?,
        vertical: j['vertical'] as String?,
        country: j['country'] as String?,
      );

  String titleFor(String locale) {
    switch (locale) {
      case 'kk':
        return titleKk ?? titleRu ?? titleUz ?? titleEn ?? '';
      case 'ru':
        return titleRu ?? titleUz ?? titleEn ?? '';
      case 'en':
        return titleEn ?? titleRu ?? titleUz ?? '';
      case 'uz':
      default:
        return titleUz ?? titleRu ?? titleEn ?? '';
    }
  }
}

class BannerApi {
  BannerApi._();
  static final BannerApi instance = BannerApi._();

  final _api = ApiClient.instance;

  Future<List<HomeBanner>> list({String? vertical, String? country}) async {
    final res = await _api.get('/api/banners', query: {
      if (vertical != null && vertical.isNotEmpty) 'vertical': vertical,
      if (country != null && country.isNotEmpty) 'country': country,
    });
    final raw = res.data;
    final list = raw is List
        ? raw
        : (raw is Map && raw['banners'] is List
            ? raw['banners'] as List
            : const <dynamic>[]);
    return list
        .map((j) => HomeBanner.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  /// Fire-and-forget — best effort. We swallow failures so a flaky network
  /// doesn't block the deep-link navigation that follows the tap.
  Future<void> click(String bannerId) async {
    try {
      await _api.post('/api/banners/$bannerId/click');
    } catch (_) {/* ignore */}
  }
}
