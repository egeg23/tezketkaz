import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/models/catalog.dart';

void main() {
  group('Category.fromJson', () {
    test('parses minimal payload with localized name fallback', () {
      final c = Category.fromJson({
        'id': 'c1',
        'slug': 'fruits',
        'name': 'Fruits',
      });
      expect(c.id, 'c1');
      expect(c.slug, 'fruits');
      // Both nameUz and nameRu fall back to top-level `name` when localized
      // variants are absent.
      expect(c.nameUz, 'Fruits');
      expect(c.nameRu, 'Fruits');
      expect(c.children, isEmpty);
      expect(c.productCount, 0);
    });

    test('parses nested children recursively', () {
      final c = Category.fromJson({
        'id': 'c1',
        'slug': 'food',
        'nameUz': 'Oziq',
        'nameRu': 'Eda',
        'children': [
          {'id': 'c2', 'slug': 'bakery', 'name': 'Bakery'},
        ],
      });
      expect(c.children, hasLength(1));
      expect(c.children.first.id, 'c2');
      expect(c.children.first.nameUz, 'Bakery');
    });

    test('coerces numeric fields safely', () {
      final c = Category.fromJson({
        'id': 'c1',
        'sortOrder': 5,
        'productCount': 12,
      });
      expect(c.sortOrder, 5);
      expect(c.productCount, 12);
    });
  });

  group('ShopVertical', () {
    test('round-trips through fromString/toString helpers', () {
      for (final v in ShopVertical.values) {
        expect(shopVerticalFromString(shopVerticalToString(v)), v);
      }
    });

    test('falls back to other for unknown values', () {
      expect(shopVerticalFromString('unknown'), ShopVertical.other);
      expect(shopVerticalFromString(null), ShopVertical.other);
    });
  });

  group('Shop.fromJson', () {
    test('parses full payload', () {
      final s = Shop.fromJson({
        'id': 's1',
        'name': 'Korzinka',
        'vertical': 'grocery',
        'distanceKm': 1.4,
        'rating': 4.7,
        'reviewsCount': 250,
        'isOpen': false,
        'lat': 41.31,
        'lng': 69.24,
      });
      expect(s.id, 's1');
      expect(s.vertical, ShopVertical.grocery);
      expect(s.distanceKm, 1.4);
      expect(s.reviewsCount, 250);
      expect(s.isOpen, false);
      expect(s.lat, 41.31);
    });

    test('defaults missing fields', () {
      final s = Shop.fromJson({'id': 's2', 'name': 'Mini'});
      expect(s.vertical, ShopVertical.other);
      expect(s.isOpen, true);
      expect(s.distanceKm, isNull);
    });
  });

  group('UserAddress', () {
    test('toJson omits null optional fields', () {
      const a = UserAddress(
        id: 'a1',
        label: 'Home',
        fullAddress: 'Tashkent',
        lat: 41.0,
        lng: 69.0,
      );
      final j = a.toJson();
      expect(j['label'], 'Home');
      expect(j['lat'], 41.0);
      expect(j.containsKey('entrance'), false);
      expect(j['isDefault'], false);
    });

    test('fromJson reads required fields', () {
      final a = UserAddress.fromJson({
        'id': 'a2',
        'label': 'Work',
        'fullAddress': 'Office',
        'isDefault': true,
      });
      expect(a.id, 'a2');
      expect(a.isDefault, true);
    });
  });
}
