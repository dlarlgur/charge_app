import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_dialog.dart';
import '../constants/api_constants.dart';

/// 서드파티 AI(Google Gemini) 처리 동의 — App Store 5.1.1(i)/5.1.2(i) 대응.
///
/// AI 추천의 '자연어 설명 문구'는 차량 상태(연료·배터리 잔량, 연비)와 경로
/// 파생 수치(거리·도착 예상 잔량), 추천 충전소/주유소 이름을 당사 서버를 거쳐
/// Google Gemini 로 보내 생성한다. 이름·이메일·기기ID·정밀 좌표는 전송하지 않음.
///
/// 첫 사용 시 1회 고지+선택을 받고, 거부해도 추천 자체는 동일하게 동작
/// (문구만 규칙 기반으로 생성 — 서버 ai_text=false → Gemini 호출 스킵).
/// 선택은 설정 화면에서 언제든 변경 가능.
class AiConsent {
  AiConsent._();

  static Box get _box => Hive.box(AppConstants.settingsBox);

  /// null = 아직 미선택, true = 동의, false = 거부.
  static bool? get value =>
      _box.get(AppConstants.keyAiThirdPartyConsent) as bool?;

  static void set(bool granted) =>
      _box.put(AppConstants.keyAiThirdPartyConsent, granted);

  /// AI 분석 시작 전 호출. 선택이 없으면 고지 다이얼로그를 띄우고 선택을 저장.
  /// 반환값 = 동의 여부 (요청의 ai_text 로 그대로 전달).
  static Future<bool> ensure(BuildContext context) async {
    final existing = value;
    if (existing != null) return existing;

    final granted = await showAppDialog<bool>(
      context,
      icon: Icons.auto_awesome_rounded,
      title: 'AI 안내 문구 생성 동의',
      message: 'AI 추천의 설명 문구를 만들기 위해 아래 정보가\n'
          'Google Gemini(생성형 AI)로 전송됩니다.\n\n'
          '· 차량 상태: 연료·배터리 잔량, 연비\n'
          '· 경로 정보: 이동 거리, 도착 예상 잔량\n'
          '· 추천 결과: 주유소·충전소 이름, 가격\n\n'
          '이름·이메일·기기 식별자·정밀 위치 좌표는\n'
          '전송되지 않습니다.\n\n'
          '동의하지 않아도 추천 기능은 동일하게 이용할 수\n'
          '있으며, 설명 문구만 기본 형식으로 제공됩니다.\n'
          '설정에서 언제든 변경할 수 있습니다.',
      primaryLabel: '동의하고 계속',
      primaryValue: true,
      secondaryLabel: '동의 없이 계속',
      secondaryValue: false,
    );
    final result = granted ?? false; // 닫기 = 미동의로 안전하게
    set(result);
    return result;
  }
}
