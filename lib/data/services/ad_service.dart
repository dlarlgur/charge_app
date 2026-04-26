import 'dart:io';

/// AdMob 광고 단위 ID 상수.
/// 본인 디바이스가 AdMob 콘솔에 테스트 기기로 등록되어 있는 전제로 항상 실광고 ID 사용.
///
/// 인-리스트 슬롯 4 / 슬롯 8 두 자리에 노출. 두 자리는 별개 단위 ID 라야
/// AdMob 측에서 정상적으로 두 임프레션을 분리 카운트.
class AdUnitIds {
  AdUnitIds._();

  static const _slot1Android = 'ca-app-pub-8640148276009977/6658354489';
  static const _slot2Android = 'ca-app-pub-8640148276009977/5716378640';
  static const _slot1Ios = _slot1Android; // TODO: iOS 단위 발급 후 교체
  static const _slot2Ios = _slot2Android; // TODO: iOS 단위 발급 후 교체

  /// 리스트 슬롯 4 (앞쪽) 광고 단위 ID.
  static String get slot1 =>
      Platform.isIOS ? _slot1Ios : _slot1Android;

  /// 리스트 슬롯 8 (뒷쪽) 광고 단위 ID.
  static String get slot2 =>
      Platform.isIOS ? _slot2Ios : _slot2Android;

  /// list_position 별로 어떤 단위 ID 를 쓸지.
  /// 4 → slot1, 8 → slot2.
  static String forPosition(int position) =>
      position == 4 ? slot1 : slot2;
}
