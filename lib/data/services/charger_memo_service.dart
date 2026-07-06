import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'user_sync_service.dart';

/// 메모 변경 시 increment — 상세 화면이 listen 해서 rebuild.
final ValueNotifier<int> chargerMemoVersion = ValueNotifier<int>(0);

/// 충전기(호기)별 개인 메모 — "지하 1층 3번 기둥", "케이블 짧음" 등 위치·상태 기록.
///
/// StationAliasService 와 동일 구조: 로컬 Hive(동기 조회) + 로그인 회원이면
/// 서버(user_charger_memos) 미러 → 기기 변경 후 로그인하면 복원.
class ChargerMemoService {
  static const String _boxName = 'charger_memos';
  static const int _maxLength = 30;

  static Box get _box => Hive.box(_boxName);

  static String _key(String stationId, String chgerId) => '$stationId|$chgerId';

  /// 메모 조회. 없거나 빈 문자열이면 null.
  static String? get(String stationId, String chgerId) {
    final v = _box.get(_key(stationId, chgerId));
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 메모 저장. trim 후 빈 문자열이면 삭제.
  /// [mirror]=false 면 서버 미러 안 함(로그인 복원 시 루프 방지용).
  static Future<void> set(String stationId, String chgerId, String memo,
      {bool mirror = true}) async {
    final trimmed = memo.trim();
    if (trimmed.isEmpty) {
      await remove(stationId, chgerId, mirror: mirror);
      return;
    }
    final clipped =
        trimmed.length > _maxLength ? trimmed.substring(0, _maxLength) : trimmed;
    await _box.put(_key(stationId, chgerId), clipped);
    await _box.flush();
    debugPrint('[ChargerMemo] SET $stationId|$chgerId = "$clipped"');
    chargerMemoVersion.value++;
    if (mirror) {
      UserSyncService.instance.addChargerMemo(stationId, chgerId, clipped);
    }
  }

  static Future<void> remove(String stationId, String chgerId,
      {bool mirror = true}) async {
    await _box.delete(_key(stationId, chgerId));
    await _box.flush();
    debugPrint('[ChargerMemo] REMOVE $stationId|$chgerId');
    chargerMemoVersion.value++;
    if (mirror) {
      UserSyncService.instance.removeChargerMemo(stationId, chgerId);
    }
  }

  /// 로컬의 모든 메모 — [{stationId, chgerId, memo}]. 게스트→회원 이관 스냅샷용.
  static List<Map<String, dynamic>> allEntries() {
    final out = <Map<String, dynamic>>[];
    for (final k in _box.keys) {
      final key = k.toString();
      final v = _box.get(k);
      if (v is! String || v.trim().isEmpty) continue;
      final idx = key.indexOf('|');
      if (idx <= 0) continue;
      out.add({
        'stationId': key.substring(0, idx),
        'chgerId': key.substring(idx + 1),
        'memo': v.trim(),
      });
    }
    return out;
  }

  /// 글자수 제한 (UI textField maxLength 로 사용)
  static int get maxLength => _maxLength;
}
