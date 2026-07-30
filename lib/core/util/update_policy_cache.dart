import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/api_constants.dart';

/// 강제 업데이트 정책 로컬 캐시.
///
/// 스플래시의 업데이트 게이트는 bootstrap 응답이 **있을 때만** 동작했다. 그래서 응답이
/// 느리거나(4초 타임아웃) 실패하면 게이트 없이 홈으로 들어가, 최소 지원 버전 미달 기기가
/// 계속 쓰이는 구멍이 있었다(1.2.2 기기 다수가 최소 1.2.5 정책을 통과해 사용 중).
///
/// 성공한 bootstrap 의 정책을 저장해두고, 실패했을 때 그 값으로 게이트를 판단한다.
/// 캐시가 아예 없을 때만(첫 실행 + 네트워크 실패) 통과시킨다.
class UpdatePolicyCache {
  UpdatePolicyCache._();

  static const _kMin = 'update_min_supported';
  static const _kStore = 'update_store_url';
  static const _kNote = 'update_release_note';
  static const _kLatest = 'update_latest_version';

  static Box get _box => Hive.box(AppConstants.settingsBox);

  static Future<void> save(UpdatePolicy p) async {
    final min = (p.minSupportedVersion ?? '').trim();
    if (min.isEmpty) return; // 정책 없는 응답은 캐시하지 않음(기존 값 유지)
    await _box.putAll({
      _kMin: min,
      _kStore: p.storeUrl ?? '',
      _kNote: p.releaseNote ?? '',
      _kLatest: p.latestVersion ?? '',
    });
  }

  /// 캐시된 정책으로 현재 버전을 판정. 캐시가 없으면 null.
  static UpdatePolicy? evaluate(String currentVersion) {
    final min = (_box.get(_kMin) as String?)?.trim();
    if (min == null || min.isEmpty) return null;
    if (!_isBelow(currentVersion, min)) return null;
    return UpdatePolicy(
      forceUpdate: true,
      optionalUpdate: false,
      latestVersion: _str(_kLatest),
      minSupportedVersion: min,
      storeUrl: _str(_kStore),
      releaseNote: _str(_kNote),
    );
  }

  static String? _str(String key) {
    final v = (_box.get(key) as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// x.y.z 숫자 비교 (semver 패키지 없이 — 부트 경로라 의존성 최소화)
  static bool _isBelow(String current, String min) {
    final a = _parts(current);
    final b = _parts(min);
    if (a.isEmpty || b.isEmpty) return false; // 파싱 실패 시 막지 않음
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }

  static List<int> _parts(String v) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(v);
    if (m == null) return const [];
    return [
      int.tryParse(m.group(1) ?? '') ?? 0,
      int.tryParse(m.group(2) ?? '') ?? 0,
      int.tryParse(m.group(3) ?? '0') ?? 0,
    ];
  }
}
