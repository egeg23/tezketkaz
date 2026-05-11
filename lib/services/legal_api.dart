import 'api_client.dart';

/// Phase 12 — read-only legal document fetched from the backend.
///
/// `content` is markdown so the screen can render it with `flutter_markdown`
/// (or fall back to plain `Text` widgets when the package isn't bundled).
/// `updatedAt` is optional because legacy / mocked responses may omit it.
class LegalDoc {
  final String content;
  final String locale;
  final DateTime? updatedAt;

  const LegalDoc({
    required this.content,
    required this.locale,
    this.updatedAt,
  });

  factory LegalDoc.fromJson(Map<String, dynamic> j) => LegalDoc(
        content: (j['content'] as String?) ?? '',
        locale: (j['locale'] as String?) ?? 'uz',
        updatedAt: _parseDate(j['updatedAt']),
      );
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// Phase 12 — wraps `GET /api/legal/{privacy|terms|all}` endpoints.
///
/// The "all" endpoint lets us fetch both documents in one round-trip when
/// the legal screen opens — saves one request on slow networks.
class LegalApi {
  LegalApi._();
  static final LegalApi instance = LegalApi._();

  final _api = ApiClient.instance;

  /// `GET /api/legal/privacy?locale=<locale>`
  Future<LegalDoc> privacy(String locale) async {
    final res = await _api.get('/api/legal/privacy', query: {'locale': locale});
    return LegalDoc.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// `GET /api/legal/terms?locale=<locale>`
  Future<LegalDoc> terms(String locale) async {
    final res = await _api.get('/api/legal/terms', query: {'locale': locale});
    return LegalDoc.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// `GET /api/legal/all?locale=<locale>` — fetches both docs in one call.
  /// Returns `(privacy, terms)`. Falls back to two parallel single-doc calls
  /// if the combined endpoint isn't available (404 / 405).
  Future<({LegalDoc privacy, LegalDoc terms})> all(String locale) async {
    try {
      final res = await _api.get('/api/legal/all', query: {'locale': locale});
      final data = res.data;
      if (data is Map &&
          data['privacy'] is Map &&
          data['terms'] is Map) {
        return (
          privacy: LegalDoc.fromJson(
              Map<String, dynamic>.from(data['privacy'] as Map)),
          terms: LegalDoc.fromJson(
              Map<String, dynamic>.from(data['terms'] as Map)),
        );
      }
    } on ApiException catch (e) {
      // 404/405 → endpoint not yet deployed. Fall through to single calls.
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
    }
    final results = await Future.wait([privacy(locale), terms(locale)]);
    return (privacy: results[0], terms: results[1]);
  }
}
