# 지도 마커 클러스터링 — 작업 인계 문서

> 다음 세션이 컨텍스트 없이 바로 이어가기 위한 인계 노트.
> systematic-debugging 으로 root cause 까지 확정한 상태. 구현 전 brainstorming → writing-plans 권장.

## 1. 문제 (root cause 확정됨)

**증상**: 지도 탭·AI 탭에서 확대/축소·이동 제스처가 버벅이고 줌 레벨이 튐.
사용자 결정적 단서 — "필터로 마커 다 끄면 정상, 켜면 이상".

**Root cause**: `map_screen.dart` 의 `_updateMarkers()` 가 최대 **300개 마커**
(가스 150 + EV 150, `_spreadSample` 으로 150 제한)를 각자 **위젯 기반 비트맵
아이콘**(`NOverlayImage.fromWidget`)으로 생성해 `NMarker` 로 지도에 올림.
NaverMap 네이티브가 카메라 이동/줌 시 이 300개 비트맵 마커를 매 프레임
재배치·렌더 → 프레임 드랍 → 제스처 끊김.

`_updateMarkers` 실행 시점이 아니라 **마커가 떠 있는 상태 자체**가 부하다.

**이미 적용된 것** (이번 세션, 커밋 65137d2): NaverMap 위젯을 State 필드로
캐싱(`_cachedMap` / `_buildMap()`) — 별개 개선이고 무해하지만 제스처 끊김의
주범은 아니었음. 그대로 두면 됨.

## 2. 해결 방향 — 사용자 선택: 클러스터링 ("제대로")

`NMarker` → `NClusterableMarker` 로 전환. NaverMap 네이티브 클러스터링이
줌 레벨·화면 거리 기반으로 가까운 마커를 자동 병합 → 화면 마커 수를
10~30개로 격감 → 제스처 부하 해소.

## 3. flutter_naver_map 1.4.4 클러스터링 API (조사 완료)

- **`NClusterableMarker`** — `NMarker` 와 거의 동일, `tags: Map<String,String>`
  파라미터 추가 (병합 전략용). icon/position/id/onTapListener 다 동일.
  정의: `lib/src/type/map/overlay/clustering/clusterable_marker.dart`
- **`NaverMapClusteringOptions`** — NaverMap 위젯의 `clusterOptions` 로 전달:
  ```dart
  NaverMapClusteringOptions(
    enableZoomRange: NInclusiveRange(0, 20),
    animationDuration: Duration(milliseconds: 300),
    mergeStrategy: NClusterMergeStrategy(
      willMergedScreenDistance: { NInclusiveRange(0,20): 35 },  // 줌별 병합 px 거리
    ),
    clusterMarkerBuilder: (NClusterInfo info, NClusterMarker clusterMarker) {
      // info.size = 묶인 개수, info.position = 중심 좌표
      // clusterMarker.setIcon(...) / setCaption(...) — 동기 콜백!
    },
  )
  ```
- **clusterMarkerBuilder 는 동기 콜백** — `NOverlayImage.fromWidget` (Future)
  을 콜백 안에서 await 불가. 클러스터 아이콘은 **미리 생성**해 두고
  `clusterMarker.setIcon(preBuiltIcon)`, 개수는 `setCaption(NOverlayCaption(
  text: info.size.toString(), ...))` 로 표시 (패키지 example 패턴).
- 추가/탭: `controller.addOverlay(NClusterableMarker)` 동일. 단일 마커 탭은
  `setOnTapListener` 그대로. **클러스터로 병합된 마커는 개별 리스너 미작동** —
  클러스터 마커 탭 동작은 별도 처리(보통 줌인) 필요.
- 일반 `NMarker` 와 혼용 가능 (클러스터링은 `NClusterableMarker` 에만 적용).

## 4. 작업 범위 / 변경 파일

| 파일 | 변경 |
|------|------|
| `lib/ui/map/map_screen.dart` | `_updateMarkers()` 전면 재작성 — `NMarker`→`NClusterableMarker`, 커스텀 `_groupByCluster`(같은 GPS 그룹화) 제거(네이티브가 대체). `_cachedMap` 의 `NaverMap` 에 `clusterOptions` 추가. 클러스터 마커 아이콘/탭 처리 |
| `lib/ui/ai/ai_main_screen.dart` | AI 탭 지도도 마커 쓰면 동일 전환 (`_buildMap()` 의 NaverMap 에 clusterOptions). 마커 생성 로직 확인 필요 |
| `lib/ui/widgets/gas_station_map_badge.dart` | 클러스터 마커용 아이콘 빌더 추가 (원형 + 개수). 기존 단일 마커 배지는 유지 |

주의: `_cachedMap` 캐싱과 `clusterOptions` 공존 — clusterOptions 도 NaverMap
생성 시 1회 고정되므로 캐싱과 충돌 없음.

## 5. 다음 세션 brainstorming 에서 정할 것 (미결정)

1. **클러스터 마커 디자인** — 원형 배지 + 개수 숫자? 색상(가스 파랑/EV 초록 구분?
   섞이면?)? 크기를 개수에 따라 키울지
2. **줌별 병합 거리** (`willMergedScreenDistance`) — 기본 35px? 줌 레벨별 차등?
3. **클러스터 탭 동작** — 탭하면 그 영역으로 줌인? 목록 시트?
4. **가스/EV 클러스터 분리** — `tags` 로 가스끼리·EV끼리만 병합할지, 섞을지
5. **단일 마커**(클러스터 안 된 것) — 기존 가격/상태 배지 그대로 유지 (확정)

## 6. 검증 방법

- 마커 많은 지역에서 줌아웃 → 클러스터로 묶이는지
- 클러스터 떠 있는 상태로 확대/축소·드래그 → 제스처 부드러운지 (이게 핵심 목표)
- 줌인 → 클러스터 풀려 개별 마커 되는지
- 단일 마커 탭 → 기존처럼 상세 시트, 클러스터 탭 → 줌인

## 7. 이번 세션에서 함께 끝낸 것 (참고)

- 위젯 v2: 5종 위젯 Bold 디자인, 새로고침 버튼+스피너, resize 2~4행,
  전일변동 ▼▲, 브랜드 심볼 로고 — 전부 커밋·푸시 완료
- 알림(Android Auto): semanticAction/visibility 패치는 `flutter_local_notifications`
  19.4 pub get 이 회사망에서 막혀 **미완** — 별도 후속. pubspec 은 18.0.0 그대로일
  수 있으니 확인 필요 (이 부분도 다음 세션 과제)
- 지도 NaverMap 캐싱 — 적용·푸시 완료

## 8. 미해결 잔여 과제

- **위치 검색 → 마커 표시** (이슈 2): 지도 상단 검색에서 장소 선택 시 현재는
  카메라만 이동, 검색 위치에 마커가 안 찍힘. 클러스터링 작업 후 이어서.
- **알림 Android Auto** semanticAction — pub.dev 접속 가능한 망에서
  `flutter_local_notifications: ^19.4.0` pub get 후 재개.
