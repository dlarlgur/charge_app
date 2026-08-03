import 'package:hive_flutter/hive_flutter.dart';

import '../constants/api_constants.dart';

/// 마지막으로 안내를 시작한 내비 앱 — 다음 번 길안내 시트에서 미리 선택해 둔다.
/// (시트 하단 "다음에도 이 앱으로 바로 열어드려요" 안내와 짝)
///
/// 경로 미리보기 엔진(RouteEnginePref)과는 별개다. 그쪽은 AI 분석에 쓸 경로를 어느
/// 엔진으로 뽑을지이고, 이건 '실제로 어떤 앱을 열어줄지'라 사용자가 다르게 고를 수 있다.
class NavAppPref {
  NavAppPref._();

  static const _key = 'nav_app';

  /// nav_app 을 저장하던 시점의 route_engine 값.
  /// 이게 지금 route_engine 과 다르면 = 그 뒤에 경로 엔진을 바꿨다는 뜻이라 그쪽을 따라간다.
  static const _engineAtKey = 'nav_app_engine_at';
  static const _engineKey = 'route_engine'; // RouteEnginePref._key 와 동일

  static const tmap = 'tmap';
  static const naver = 'naver';
  static const kakao = 'kakao';

  static const _all = {tmap, naver, kakao};

  /// 우선순위
  ///   ① 경로 엔진을 마지막 선택 이후에 바꿨다면 → 그 엔진
  ///      (티맵으로 경로를 다시 뽑았는데 안내는 카카오로 열리면 이상하다 — 형 제보)
  ///   ② 마지막으로 안내를 시작한 앱 ("다음에도 이 앱으로 바로 열어드려요")
  ///   ③ 경로 엔진
  ///   ④ 티맵
  static String get() {
    final box = Hive.box(AppConstants.settingsBox);
    final engine = box.get(_engineKey);
    final saved = box.get(_key);
    final engineAt = box.get(_engineAtKey);

    // 저장 이후 경로 엔진이 바뀌었으면 사용자의 최신 의사는 그쪽이다.
    if (_all.contains(engine) && engine != engineAt) return engine as String;
    if (_all.contains(saved)) return saved as String;
    if (_all.contains(engine)) return engine as String;
    return tmap;
  }

  static Future<void> set(String v) async {
    if (!_all.contains(v)) return;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put(_key, v);
    // 이 선택이 '어느 경로 엔진 시절의 것인지' 를 같이 남긴다 (위 ① 판정용)
    await box.put(_engineAtKey, box.get(_engineKey));
  }

  static String label(String v) {
    switch (v) {
      case naver:
        return '네이버';
      case kakao:
        return '카카오내비';
      default:
        return '티맵';
    }
  }

  /// '앱이름 + 으로/로' — 받침 유무로 조사를 고른다.
  /// (티맵으로 / 네이버로 / 카카오내비로 — 한 벌로 붙이면 "네이버으로"가 된다)
  static String labelWithRo(String v) {
    final s = label(v);
    final last = s.codeUnitAt(s.length - 1);
    // 한글 음절 영역이면 종성 인덱스로 판정. ㄹ(8) 받침은 '로'.
    final jong = (last >= 0xAC00 && last <= 0xD7A3) ? (last - 0xAC00) % 28 : -1;
    final needsEu = jong > 0 && jong != 8;
    return '$s${needsEu ? '으로' : '로'}';
  }
}
