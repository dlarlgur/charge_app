/// 디자인 토큰 — 라운드/간격/투명도 일관 기준.
///
/// 신규 코드는 이 토큰을 사용하고, 기존 하드코딩 값은 점진적으로 정리.
class AppRadius {
  AppRadius._();

  /// 4 — 작은 칩, 닷 인디케이터.
  static const double xs = 4;

  /// 8 — 칩, 인풋 안의 작은 컨테이너.
  static const double sm = 8;

  /// 10 — 입력 박스, 작은 카드.
  static const double md = 10;

  /// 12 — 표준 카드.
  static const double lg = 12;

  /// 14 — 강조 카드.
  static const double xl = 14;

  /// 16 — 헤더 카드, 큰 컨테이너.
  static const double xl2 = 16;

  /// 20 — 모달 시트 상단 corner.
  static const double xl3 = 20;

  /// 24 — bottom sheet 상단 corner (메인).
  static const double sheet = 24;

  /// pill — 둥근 알약 형태 (FAB, 토글).
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();

  /// 2
  static const double xxs = 2;

  /// 4
  static const double xs = 4;

  /// 6
  static const double sm6 = 6;

  /// 8
  static const double sm = 8;

  /// 10
  static const double md10 = 10;

  /// 12 — 카드 안 row 간격, 일반 vertical gap.
  static const double md = 12;

  /// 14
  static const double lg14 = 14;

  /// 16 — 화면 좌우 horizontal padding 표준.
  static const double lg = 16;

  /// 20
  static const double xl = 20;

  /// 24 — 섹션 간 vertical gap.
  static const double xl2 = 24;

  /// 32
  static const double xl3 = 32;
}

/// 흔히 쓰는 알파값. `Color.withValues(alpha: AppOpacity.subtle)` 형태로.
class AppOpacity {
  AppOpacity._();

  /// 0.04 — 거의 투명, 매우 연한 hover.
  static const double faint = 0.04;

  /// 0.08 — 다크모드 카드 살짝 lift.
  static const double subtle = 0.08;

  /// 0.10 — 컬러 칩 배경.
  static const double soft = 0.10;

  /// 0.12 — 활성 칩 배경.
  static const double medium = 0.12;

  /// 0.18 — 강조 컬러 배경.
  static const double moderate = 0.18;

  /// 0.30 — 보더, 그림자.
  static const double strong = 0.30;
}
