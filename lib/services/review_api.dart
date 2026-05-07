import '../models/review.dart';
import 'api_client.dart';

/// Reviews endpoints (Phase 3, Agent B backend).
class ReviewApi {
  ReviewApi._();
  static final ReviewApi instance = ReviewApi._();

  final _api = ApiClient.instance;

  /// `POST /api/orders/:orderId/reviews`
  Future<Review> create(
    String orderId, {
    required String targetType,
    required String targetId,
    required int rating,
    String? text,
    List<String>? photos,
  }) async {
    final res = await _api.post('/api/orders/$orderId/reviews', {
      'targetType': targetType.toUpperCase(),
      'targetId': targetId,
      'rating': rating,
      if (text != null && text.isNotEmpty) 'text': text,
      if (photos != null && photos.isNotEmpty) 'photos': photos,
    });
    final data = res.data;
    final m = (data is Map && data['review'] is Map)
        ? Map<String, dynamic>.from(data['review'] as Map)
        : Map<String, dynamic>.from(data as Map);
    return Review.fromJson(m);
  }

  /// `GET /api/reviews?targetType=&targetId=&cursor=&limit=`
  Future<List<Review>> list({
    required String targetType,
    required String targetId,
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _api.get('/api/reviews', query: {
      'targetType': targetType.toUpperCase(),
      'targetId': targetId,
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    final data = res.data;
    final list = (data is List)
        ? data
        : (data is Map && data['reviews'] is List
            ? data['reviews'] as List
            : const []);
    return list
        .map((r) => Review.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
