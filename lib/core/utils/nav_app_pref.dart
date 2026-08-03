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

  static const tmap = 'tmap';
  static const naver = 'naver';
  static const kakao = 'kakao';

  static const _all = {tmap, naver, kakao};

  /// 우선순위: ① 마지막으로 안내를 시작한 앱 ② 경로 미리보기 엔진(RouteEnginePref 와
  /// 같은 Hive 키) ③ 티맵. 카카오로 경로를 뽑아 보던 사용자가 시트를 열면 카카오가
  /// 미리 잡혀 있어야 자연스럽다 — 단 한 번이라도 직접 고른 앱이 있으면 그게 이긴다
  /// ("다음에도 이 앱으로 바로 열어드려요" 약속).
  static String get() {
    final box = Hive.box(AppConstants.settingsBox);
    final v = box.get(_key);
    if (_all.contains(v)) return v as String;
    final engine = box.get('route_engine'); // RouteEnginePref._key 와 동일
    if (_all.contains(engine)) return engine as String;
    return tmap;
  }

  static Future<void> set(String v) async {
    if (!_all.contains(v)) return;
    await Hive.box(AppConstants.settingsBox).put(_key, v);
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
