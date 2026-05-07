import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/models/review.dart';

void main() {
  group('Review.fromJson author fallbacks', () {
    test('prefers reviewerName when present', () {
      final r = Review.fromJson({
        'id': 'r1',
        'targetType': 'shop',
        'targetId': 's1',
        'reviewerName': 'Ali',
        'authorName': 'Ignored',
        'rating': 5,
      });
      expect(r.authorName, 'Ali');
    });

    test('falls back to nested author.name', () {
      final r = Review.fromJson({
        'id': 'r2',
        'targetType': 'shop',
        'targetId': 's1',
        'author': {'name': 'Vali', 'avatarUrl': 'https://x'},
        'rating': 4,
      });
      expect(r.authorName, 'Vali');
      expect(r.authorAvatar, 'https://x');
    });

    test('falls back to authorName, then userName', () {
      final r = Review.fromJson({
        'id': 'r3',
        'targetType': 'shop',
        'targetId': 's1',
        'authorName': 'Abdulloh',
        'rating': 3,
      });
      expect(r.authorName, 'Abdulloh');

      final r2 = Review.fromJson({
        'id': 'r4',
        'targetType': 'shop',
        'targetId': 's1',
        'userName': 'Bekzod',
        'rating': 3,
      });
      expect(r2.authorName, 'Bekzod');
    });
  });

  group('Review.fromJson fields', () {
    test('reads photos and text from legacy "comment" alias', () {
      final r = Review.fromJson({
        'id': 'r1',
        'targetType': 'shop',
        'targetId': 's1',
        'rating': 5,
        'comment': 'Yaxshi',
        'photos': ['a.jpg', 'b.jpg'],
      });
      expect(r.text, 'Yaxshi');
      expect(r.photos, hasLength(2));
    });

    test('defaults rating to 5 when missing', () {
      final r = Review.fromJson({
        'id': 'r1',
        'targetType': 'shop',
        'targetId': 's1',
      });
      expect(r.rating, 5);
    });

    test('parses authorId from various id field aliases', () {
      final a = Review.fromJson({
        'id': 'r1',
        'targetType': 'shop',
        'targetId': 's1',
        'rating': 5,
        'reviewerId': 'u1',
      });
      expect(a.authorId, 'u1');

      final b = Review.fromJson({
        'id': 'r2',
        'targetType': 'shop',
        'targetId': 's1',
        'rating': 5,
        'userId': 'u2',
      });
      expect(b.authorId, 'u2');
    });
  });
}
