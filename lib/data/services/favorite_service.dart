import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';

class FavoriteService {
  static final _box = Hive.box(AppConstants.favoritesBox);

  static void add({required String id, required String type, required String name, required String subtitle}) {
    _box.put('${type}_$id', {
      'id': id,
      'type': type,
      'name': name,
      'subtitle': subtitle,
      'addedAt': DateTime.now().toIso8601String(),
    });
  }

  static void remove(String id, String type) {
    _box.delete('${type}_$id');
  }

  static bool isFavorite(String id, String type) {
    return _box.containsKey('${type}_$id');
  }

  static bool toggle({required String id, required String type, required String name, required String subtitle}) {
    if (isFavorite(id, type)) {
      remove(id, type);
      return false;
    } else {
      add(id: id, type: type, name: name, subtitle: subtitle);
      return true;
    }
  }

  static List<Map<String, dynamic>> getAll() {
    return _box.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList()
      ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));
  }

  static List<Map<String, dynamic>> getByType(String type) {
    return getAll().where((f) => f['type'] == type).toList();
  }

  static Set<String> idSetByType(String type) {
    return _box.keys
        .where((k) => k.toString().startsWith('${type}_'))
        .map((k) => k.toString().substring(type.length + 1))
        .toSet();
  }
}
