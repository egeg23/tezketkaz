/// Reviews — matches `GET /api/reviews` and `POST /api/orders/:id/reviews`.
class Review {
  final String id;
  /// 'shop' | 'courier' | 'product'
  final String targetType;
  final String targetId;
  final String? authorId;
  final String? authorName;
  final String? authorAvatar;
  final int rating; // 1..5
  final String? text;
  final List<String> photos;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.targetType,
    required this.targetId,
    this.authorId,
    this.authorName,
    this.authorAvatar,
    required this.rating,
    this.text,
    this.photos = const [],
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        targetType: (j['targetType'] ?? '').toString(),
        targetId: (j['targetId'] ?? '').toString(),
        authorId: j['reviewerId']?.toString() ??
            j['authorId']?.toString() ??
            j['userId']?.toString(),
        authorName: j['reviewerName'] as String? ??
            j['author']?['name'] as String? ??
            j['authorName'] as String? ??
            j['userName'] as String?,
        authorAvatar: j['reviewerAvatar'] as String? ??
            j['author']?['avatarUrl'] as String? ??
            j['authorAvatar'] as String?,
        rating: (j['rating'] as num?)?.toInt() ?? 5,
        text: j['text'] as String? ?? j['comment'] as String?,
        photos: (j['photos'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        createdAt: DateTime.tryParse(
                (j['createdAt'] ?? j['date'] ?? '').toString()) ??
            DateTime.now(),
      );
}
