# 즐겨찾기 위젯 V2 — Bold 디자인

## 출처
사용자 제공 `widget.html` (별첨 mockup) — 디자인 결정 완료. 이 spec 은 RemoteViews 매핑 가이드.

## 범위
| 위젯 | 파일 | 신/구 |
|------|------|------|
| Medium 가스 | `widget_gas.xml` + `GasWidgetProvider.kt` | 갱신 |
| Medium EV | `widget_ev.xml` + `EvWidgetProvider.kt` | 갱신 |
| Large 통합 | `widget_combined.xml` + `CombinedWidgetProvider.kt` | 신규 |
| Small 가스 최저가 | `widget_gas_small.xml` + `GasSmallWidgetProvider.kt` | 신규 |
| Small EV 가용 | `widget_ev_small.xml` + `EvSmallWidgetProvider.kt` | 신규 |

**제외**: 거리(km) 표시 — 위젯에 ACCESS_FINE_LOCATION 권한 + WorkManager isolate 위치 조회 별도 작업. 가격 변동(▼/▲) — 전일 가격 캐시/서버 API 별도 작업. 둘 다 별도 PR.

## 디자인 토큰 (`colors.xml` 추가)
```
ink #0F172A | ink-2 #334155 | muted #64748B | mute-2 #94A3B8
line #E2E8F0 | line-soft #F1F5F9
blue #2563EB | blue-2 #3B82F6 | blue-soft #EFF6FF
green #10B981 | green-2 #059669 | green-soft #ECFDF5
amber #F59E0B | amber-soft #FEF3C7 | red #EF4444
```

## 폰트 (이미 등록된 Pretendard 5단계 활용)
- ExtraBold 800 → 가격/슬롯 큰 숫자 + 위젯 타이틀 + 이름
- SemiBold 600 → sub 라인 + pill 텍스트
- Bold 700 → meta + section title
- Regular 400 → 단위 (`원`, `/`, `kW`)

API 26+ 에서 `android:fontFeatureSettings="tnum"` 으로 수치 정렬 (가격/슬롯 행 정렬용).

## drawable 자원
| 파일 | 용도 |
|------|------|
| `bg_widget_card.xml` | 흰 98% + radius 22dp (Medium/Large) |
| `bg_widget_card_dense.xml` | radius 18dp (Small) |
| `bg_badge_gs.xml` | #0EA5E9, radius 10dp |
| `bg_badge_hd.xml` | #16A34A, radius 10dp |
| `bg_badge_skn.xml` | #DC2626, radius 10dp |
| `bg_badge_soil.xml` | #FFCC00, radius 10dp (글자 ink) |
| `bg_badge_rto.xml` | ink-2 솔리드 |
| `bg_badge_default.xml` | mute-2 솔리드 |
| `bg_badge_ev_slow.xml` | gradient #34D399→#059669 |
| `bg_badge_ev_fast.xml` | gradient #3B82F6→#2563EB |
| `bg_pill_neutral.xml` | line-soft, radius 99dp (셀프/일반/완속/급속 sub) |
| `bg_pill_status_avail.xml` | green-soft (`여유 가용`) |
| `bg_pill_status_busy.xml` | amber-soft (`충전 중`) |
| `bg_pill_status_full.xml` | red-tint (`만석`) |
| `bg_pill_speed_slow.xml` | blue-soft |
| `bg_pill_speed_fast.xml` | green-soft |
| `bg_row_best_gas.xml` | gradient: blue 6% alpha → transparent, angle 0, radius 10dp |
| `bg_row_best_ev.xml` | gradient: green 6% alpha → transparent, angle 0, radius 10dp |
| `ic_widget_mark_gas.xml` | vector: 주유기 + blue gradient |
| `ic_widget_mark_ev.xml` | vector: 번개 + green gradient |
| `ic_widget_mark_combined.xml` | vector: split blue/green |
| `ic_star_filled.xml` | vector: amber star |
| `ic_live_dot.xml` | vector: green dot with halo (실시간 표시) |

## Medium 레이아웃 구조
```
[FrameLayout @bg_widget_card  padding 16dp]
  [LinearLayout vertical]
    [LinearLayout horizontal weight 22dp]  ← header
      [ImageView 22dp @ic_widget_mark_xxx]
      [TextView "즐겨찾기 주유소" 13sp 800w]
      [Space weight=1]
      [LinearLayout horizontal]
        [ImageView 5dp @ic_live_dot]
        [TextView "실시간 · 09:41" 11sp 700w mute-2]
    [Space 12dp]
    [LinearLayout horizontal padding 7dp]  ← row1 (best 면 @bg_row_best_xxx)
      [TextView 34dp @bg_badge_xxx text=brandShort]
      [LinearLayout vertical width=0 weight=1]
        [LinearLayout horizontal]
          [TextView name 13sp 800w ellipsize end]
          [ImageView 11dp @ic_star_filled]
        [LinearLayout horizontal margin-top 1dp]
          [TextView @bg_pill_neutral text="셀프|일반|완속|급속" 10sp 700w ink-2]
          [TextView sub-rest "휘발유" 또는 "7kW" 10.5sp 600w muted]
      [LinearLayout vertical end]
        [LinearLayout horizontal baseline]
          [TextView price/avail 18sp 800w ink/green/red]
          [TextView "원" 또는 "/total" 11sp 700w muted]
        [TextView @bg_pill_status_xxx (EV 전용) "여유 가용" 10sp 800w]
    [Space 4dp]
    [...row2 동일 구조...]
```

빈 상태: row1 의 badge text="+", bg `bg_badge_default`, name="즐겨찾기 주유소를 추가하세요", sub 숨김, price-area 숨김. row2 visibility GONE.

## Large 레이아웃
- 헤더 mark = split 아이콘, title = `기름반 전기반`
- section-title (가스): swatch 9dp blue + "주유 · 휘발유 기준" 11sp 800w muted
- 가스 row1, row2
- divider (`line-soft` 1dp + margin-top 10dp)
- section-title (EV): swatch green + "충전 · 잔여 자리"
- EV row1, row2

높이 ~368dp, 폭 4셀.

## Small 레이아웃 (2x2)
**가스 최저가**:
```
[card padding 14dp]
  [header]  mark gas + "주유 최저가" 13sp 800w
  [Space weight=1] [LinearLayout vertical]
  [name 2-line max 13sp 800w]
  [sub "휘발유 · 셀프" 10.5sp 700w muted]
  [Space margin-top=auto]
  [LinearLayout horizontal baseline]
    [TextView price 34sp 800w blue]
    [TextView "원/L" 11sp 700w muted]
  [foot]
    [TextView fuelLabel 10.5sp 700w ink-2]
```

**EV 가용**:
```
[card]
  [header]  mark ev + "충전 가용"
  [body]
  [name 2-line 13sp 800w]
  [sub "완속 7kW" 10.5sp 700w muted]
  [Space]
  [LinearLayout horizontal baseline]
    [TextView available 34sp 800w green|red]
    [TextView "/{total} 자리" 11sp 700w muted]
  [TextView @bg_pill_status_xxx 10sp 800w]
```

## Provider 로직
모든 Provider 가 같은 prefs(`HomeWidgetPreferences`)의 `widget_gas_list`/`widget_ev_list` 읽음. WidgetService 변경 최소 (`updateAll` 한 번이 모든 위젯 갱신).

- **GasWidgetProvider/EvWidgetProvider** (Medium): list[0..2) 읽어 row1/row2 채움. row1 을 `bg_row_best_*` 로 항상 강조 (정렬은 widget_service 에서 가격/가용순으로 보장).
- **CombinedWidgetProvider** (Large): gas list[0..2) + ev list[0..2) 둘 다 채움.
- **GasSmallWidgetProvider** (Small): gas list[0] 만. 없으면 빈 상태 ("주유소 추가하세요" + 흰 +배지).
- **EvSmallWidgetProvider** (Small): ev list[0] 만.

**EV statusCode → status pill 매핑**:
- 0 (available > 0): `bg_pill_status_avail` + "여유 가용"
- 1 (busy, available = 0): `bg_pill_status_busy` + "충전 중"
- 2 (broken ≥ total): `bg_pill_status_full` + "점검 중"

**EV speed sub pill**:
- maxKw < 50: `bg_pill_speed_slow` + "완속"
- maxKw ≥ 50: `bg_pill_speed_fast` + "급속"

**가스 sub pill**:
- isSelf == true: `bg_pill_neutral` + "셀프"
- 아니면: `bg_pill_neutral` + "일반"

**Star 표시**: 모든 즐겨찾기 행의 이름 우측에 11dp `ic_star_filled` (amber) 표시. 빈 상태 행은 표시 안 함.

## widget_service.dart 변경 사항
- 정렬 보장: `gasFavs` 는 price asc (저렴한 순), `evFavs` 는 available desc (가용 많은 순). 동일하면 addedAt desc.
- 그 외 필드 그대로 (id/name/brand/price/isSelf/fuelLabel · id/name/available/total/broken/hasFast/maxKw/statusCode).

## Manifest 변경
신규 receiver 3개 (`CombinedWidgetProvider`, `GasSmallWidgetProvider`, `EvSmallWidgetProvider`) 추가. `widget_info` XML 3개 신규.

| Provider | minWidth | minHeight | targetCellWidth | targetCellHeight |
|----------|----------|-----------|-----------------|------------------|
| Combined (Large) | 250dp | 250dp | 4 | 4 |
| GasSmall | 110dp | 110dp | 2 | 2 |
| EvSmall | 110dp | 110dp | 2 | 2 |

미리보기(preview) drawable 은 단순화: 각 위젯 빈 상태 PNG 또는 layout preview (`android:previewLayout`).

## 검증
- 빌드/설치 후 폰 홈 화면에 5종 위젯 모두 추가
- 즐겨찾기 데이터 있을 때 표시 정상, 빈 상태 fallback 정상
- 가스: best 행 highlight + 셀프/일반 pill + 가격 큰 폰트 노출 확인
- EV: best 행 + 완속/급속 pill + status pill (여유/충전중/점검) + 슬롯 a/b 큰 폰트 확인
- Small: 한 행 표시, 큰 숫자
- Large: 가스/EV 한 카드 안에서 분리 표시

차량(안드로이드 오토)/알림 흐름과 무관 (이 PR 범위 아님).
