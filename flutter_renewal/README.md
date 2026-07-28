# AI 탭 리뉴얼 — Flutter 적용 코드

`AI 탭 리뉴얼.dc.html` 디자인을 Flutter 위젯으로 옮긴 것입니다.
모두 기존 코드 컨벤션(`ai_constants.dart` 의 `kInk/kMute2/modeAccent…`, `AppColors`)을 그대로 씁니다.

## 배치 위치

전부 `lib/ui/ai/widgets/` 안에 둡니다. (import 경로가 그 기준입니다)

| 파일 | 교체 대상 | 변경 요지 |
|---|---|---|
| `gauge_ring.dart` | `widgets/gauge_ring.dart` **교체** | 게이지 중앙을 "잔량 N% + 주행가능 km" 로, **우하단 편집 뱃지** 추가, "갈 수 있어요" 문구 제거, km↔편집버튼 겹침 해소 |
| `hero_card.dart` | `widgets/hero_card.dart` **교체** | divider 제거·간결화, 선호 조건 칩 = **주유는 [고속도로] 하나만**, 충전은 [급속][완속][고속도로] |
| `level_edit_sheet.dart` | `widgets/level_edit_sheet.dart` **교체** | 상단 그라데이션 요약 카드, **컬러존 슬라이더**(위험/주의/충분), 목표 세그먼트 버튼화 |
| `recommended_gas_card.dart` | `ai_result_screen.dart` 의 `_RecommendedCard` 참고/교체 | 추천 카드 정돈 + **절약액** 강조(amber 통일) |
| `ev_recommended_card.dart` | `ev_result_screen.dart` 의 `_StationCard(isRecommended)` 참고/교체 | 상태 헤더 + **도착/충전후 SOC 예측 바** + 정보 칩 |

`gauge_ring.dart` · `hero_card.dart` · `level_edit_sheet.dart` 는 **생성자 시그니처가 기존과 동일**해서 파일만 바꾸면 됩니다.

## 결과 카드 사용 예

추천 카드 2종은 호출부 데이터에 맞춰 끼워 넣습니다. 로고는 기존 `BrandLogo` 위젯을 그대로 넘기세요.

```dart
RecommendedGasCard(
  logo: BrandLogo(brand: brandCode, stationName: name),
  stationName: 'SK 서초로주유소',
  subtitle: 'SK에너지 · 1.2km · 셀프',
  pricePerLabel: wonFmt.format(1617),
  detourLabel: '+3분',          // 우회 없으면 '우회 없음'
  savings: 2700,                // 0 이하면 '—'
  isDetour: true,
  onViewMap: _viewOnMap,
  onNavigate: _startNavigation,
);

EvRecommendedCard(
  logo: operatorLogo,
  stationName: '평창휴게소 (강릉방향)',
  subtitle: '한전 KEPCO · 영동고속도로',
  availCount: 3, totalCount: 4,
  arrivalSoc: 17, afterChargeSoc: 88, chargeMinutes: 15,
  unitPriceLabel: '347원/kWh · 100kW',
  distanceLabel: '98km',
  onRoute: true,
  onNavigate: _startNavigation,
  onAlarm: _toggleWatch,
  onDetail: _openDetail,
);
```

## 색상 매핑 (디자인 시스템 그대로)

- 주유 accent `#3B82F6` (deep `#2563EB`) / 충전 accent `#10B981` (deep `#059669`)
- 추천 강조 amber `#F59E0B`, 절약/여유 green `#22C55E/#16A34A`
- 잔량 구간색: ≤20% `#EF4444` · ≤50% `#F59E0B` · 그 이상 `#22C55E`

> 참고: 위 파일들은 정적 분석 기준으로 작성했지만 실제 프로젝트에서 `flutter analyze` 한 번 돌려 import 경로/버전(예: `withValues(alpha:)` 는 Flutter 3.27+)만 확인하세요.
