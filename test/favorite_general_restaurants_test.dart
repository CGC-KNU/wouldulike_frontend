import 'package:flutter_test/flutter_test.dart';
import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/services/affiliate_service.dart';

GeneralRestaurantSummary _general({
  int id = 0,
  String name = '',
  String address = '',
  String url = '',
  String category = 'KOREAN',
}) {
  return GeneralRestaurantSummary.fromJson(<String, dynamic>{
    'restaurant_id': id,
    'name': name,
    'description': '',
    'address': address,
    'category': category,
    'zone': '',
    'phone_number': '',
    'url': url,
  });
}

void main() {
  test('찜 키는 id > url > 이름+주소 순으로 떨어진다', () {
    expect(generalRestaurantFavoriteKey(_general(id: 7)), 'id:7');
    expect(
      generalRestaurantFavoriteKey(_general(url: 'https://a.b')),
      'url:https://a.b',
    );
    expect(
      generalRestaurantFavoriteKey(_general(name: '가게', address: '한밭로 1')),
      'name:가게|addr:한밭로 1',
    );
  });

  test('아직 로드되지 않은 찜은 저장해 둔 스냅샷으로 살아난다', () {
    final merged = mergeFavoriteGeneralRestaurants(
      loaded: [_general(id: 1, name: '로드된집')],
      favoriteKeys: {'id:1', 'id:2'},
      snapshots: <String, dynamic>{
        'id:2': {'restaurant_id': 2, 'name': '스냅샷집', 'category': 'KOREAN'},
      },
    );
    expect(merged.map((r) => r.name).toSet(), {'로드된집', '스냅샷집'});
  });

  test('로드된 값이 스냅샷보다 우선하고, 찜하지 않은 곳은 빠진다', () {
    final merged = mergeFavoriteGeneralRestaurants(
      loaded: [
        _general(id: 1, name: '최신이름'),
        _general(id: 9, name: '안찜한집'),
      ],
      favoriteKeys: {'id:1'},
      snapshots: <String, dynamic>{
        'id:1': {'restaurant_id': 1, 'name': '옛날이름', 'category': 'KOREAN'},
      },
    );
    expect(merged.length, 1);
    expect(merged.single.name, '최신이름');
  });

  test('스냅샷이 깨져 있어도 나머지 찜은 살린다', () {
    final merged = mergeFavoriteGeneralRestaurants(
      loaded: const [],
      favoriteKeys: {'id:2', 'id:3'},
      snapshots: <String, dynamic>{
        'id:2': '깨진 값',
        'id:3': {'restaurant_id': 3, 'name': '멀쩡한집', 'category': 'KOREAN'},
      },
    );
    expect(merged.map((r) => r.name).toList(), ['멀쩡한집']);
  });
}
