import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import 'user_sync_service.dart';

/// 집/회사 등록 (네이버식) — 게스트는 Hive(설정 박스), 로그인 시 서버 미러.
/// 게스트→가입 이관은 UserDataSync 스냅샷(import)에 places 로 포함된다.
class PlaceService {
  static const kinds = ['home', 'work'];
  static String _key(String kind) => 'place_$kind'; // place_home / place_work

  static Box get _box => Hive.box(AppConstants.settingsBox);

  /// {name, address, lat, lng} 또는 null(미등록).
  static Map<String, dynamic>? get(String kind) {
    final raw = _box.get(_key(kind));
    if (raw is! String || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  /// 저장 + 로그인 상태면 서버 미러(fire-and-forget).
  static Future<void> set(String kind, Map<String, dynamic> place) async {
    await _box.put(_key(kind), jsonEncode(place));
    UserSyncService.instance.putPlace({'kind': kind, ...place});
  }

  static Future<void> remove(String kind) async {
    await _box.delete(_key(kind));
    UserSyncService.instance.removePlace(kind);
  }

  /// 서버 복원(sync) — 서버 우선 덮어쓰기 (서버 미러 재호출 없음).
  static Future<void> applyRemote(List places) async {
    for (final p in places) {
      if (p is! Map) continue;
      final kind = (p['kind'] ?? '').toString();
      if (!kinds.contains(kind)) continue;
      await _box.put(_key(kind), jsonEncode({
        'name': (p['name'] ?? '').toString(),
        'address': (p['address'] ?? '').toString(),
        'lat': p['lat'],
        'lng': p['lng'],
      }));
    }
  }

  /// 게스트→가입 이관용 스냅샷.
  static List<Map<String, dynamic>> toSnapshotList() {
    final out = <Map<String, dynamic>>[];
    for (final kind in kinds) {
      final p = get(kind);
      if (p != null) out.add({'kind': kind, ...p});
    }
    return out;
  }
}
