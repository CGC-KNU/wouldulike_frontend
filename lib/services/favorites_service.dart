import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// GET/POST /api/users/me/favorites, DELETE /api/users/me/favorites/{id}
/// 서버를 기준으로 두고, 네트워크 실패 시 로컬 캐시를 유지한다.
class FavoritesService {
  FavoritesService._();

  static const String localIdsKey = 'affiliate_favorite_restaurant_ids';

  static Future<Set<int>> loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final local = _parseIds(prefs.getStringList(localIdsKey));
    try {
      final remote = await fetchRemoteIds();
      final merged = {...local, ...remote};
      await prefs.setStringList(
        localIdsKey,
        merged.map((id) => id.toString()).toList(),
      );
      return merged;
    } catch (e) {
      debugPrint('[Favorites] remote load failed: $e');
      return local;
    }
  }

  static Future<Set<int>> fetchRemoteIds() async {
    final response = await ApiClient.get('/api/users/me/favorites');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return _idsFromResponse(decoded);
  }

  static Future<void> setFavorite(int restaurantId, bool isFavorite) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _parseIds(prefs.getStringList(localIdsKey));
    if (isFavorite) {
      next.add(restaurantId);
    } else {
      next.remove(restaurantId);
    }
    await prefs.setStringList(
      localIdsKey,
      next.map((id) => id.toString()).toList(),
    );

    try {
      if (isFavorite) {
        await ApiClient.post(
          '/api/users/me/favorites',
          body: {'restaurant_id': restaurantId},
        );
      } else {
        await ApiClient.delete('/api/users/me/favorites/$restaurantId');
      }
    } catch (e) {
      debugPrint('[Favorites] sync failed: $e');
    }
  }

  static Set<int> _parseIds(List<String>? raw) {
    if (raw == null) return <int>{};
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Set<int> _idsFromResponse(dynamic decoded) {
    final ids = <int>{};

    void addId(dynamic value) {
      if (value is int) {
        ids.add(value);
      } else if (value is num) {
        ids.add(value.toInt());
      } else if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) ids.add(parsed);
      } else if (value is Map) {
        addId(value['restaurant_id'] ?? value['id']);
      }
    }

    if (decoded is List) {
      for (final item in decoded) {
        addId(item);
      }
      return ids;
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      for (final key in ['results', 'favorites', 'ids', 'restaurant_ids']) {
        final raw = map[key];
        if (raw is List) {
          for (final item in raw) {
            addId(item);
          }
        }
      }
    }
    return ids;
  }
}
