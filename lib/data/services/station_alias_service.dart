import 'package:hive_flutter/hive_flutter.dart';

/// 충전소/주유소 별칭 — 사용자가 직접 등록한 친근한 이름.
///
/// 동기 사유: getDisplayName 은 카드/리스트/알림에서 매 빌드 호출됨.
/// async 면 setState 루프에서 깜빡임 발생 → Hive 동기 API 사용.
///
/// type: 'ev' | 'gas' — ev/가스 station id 형식이 달라 충돌 가능성 낮지만
/// 명시적으로 분리해 미래 확장(타사 station 등) 안전.
class StationAliasService {
  static const String _boxName = 'station_aliases';
  static const int _maxLength = 20;

  static Box get _box => Hive.box(_boxName);

  static String _key(String stationId, String type) => '${type}_$stationId';

  /// 별칭 조회. 없거나 빈 문자열이면 null.
  static String? get(String stationId, {required String type}) {
    final v = _box.get(_key(stationId, type));
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 별칭 저장. trim 후 빈 문자열이면 자동 삭제.
  /// [maxLength] 초과 시 잘라냄.
  static Future<void> set(String stationId, String alias, {required String type}) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) {
      await remove(stationId, type: type);
      return;
    }
    final clipped = trimmed.length > _maxLength ? trimmed.substring(0, _maxLength) : trimmed;
    await _box.put(_key(stationId, type), clipped);
  }

  static Future<void> remove(String stationId, {required String type}) async {
    await _box.delete(_key(stationId, type));
  }

  /// 표시용 이름 결정 — 별칭 있으면 별칭, 없으면 원본.
  /// 카드/리스트/지도/알림 등 거의 모든 표시 지점에서 호출.
  static String resolve(String stationId, String originalName, {required String type}) {
    final alias = get(stationId, type: type);
    return alias ?? originalName;
  }

  /// EV 편의 메서드
  static String? getEv(String stationId) => get(stationId, type: 'ev');
  static Future<void> setEv(String stationId, String alias) => set(stationId, alias, type: 'ev');
  static Future<void> removeEv(String stationId) => remove(stationId, type: 'ev');
  static String resolveEv(String stationId, String originalName) =>
      resolve(stationId, originalName, type: 'ev');

  /// 가스 편의 메서드
  static String? getGas(String stationId) => get(stationId, type: 'gas');
  static Future<void> setGas(String stationId, String alias) => set(stationId, alias, type: 'gas');
  static Future<void> removeGas(String stationId) => remove(stationId, type: 'gas');
  static String resolveGas(String stationId, String originalName) =>
      resolve(stationId, originalName, type: 'gas');

  /// 글자수 제한 (UI dialog 에서 textField maxLength 로 사용)
  static int get maxLength => _maxLength;
}
