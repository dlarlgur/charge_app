import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:charge_helper/ui/ai/widgets/hero_card.dart';

/// AI 탭 — 하단 패널이 상단 출발지·목적지 카드를 덮던 사고(형 제보 2026-08-19).
///
/// 재현 경로: 출발지·목적지를 넣으면 하단 패널에 **경로 선택 박스**(네이버 기준 ·
/// 실시간추천/큰길우선)가 추가로 붙는다. 그 상태에서 접혀 있던 잔량(Hero) 카드를
/// 다시 펼치면 패널이 그만큼 길어지면서 위로 밀려 올라가 상단 카드를 덮었다.
///
/// 원인: 상단 오버레이와 하단 패널이 각각 독립된 `Positioned` 였다. 하단은
/// `Positioned(bottom:0)` 이라 maxHeight 가 무한 — 길어지면 제한 없이 위로 자랐고,
/// Stack 에서 나중에 그려지므로 상단 카드를 그대로 덮었다.
///
/// 수정: 둘을 한 `Column` 으로 묶고 하단을 `Expanded` 안에 넣는다. 하단의 높이가
/// '상단을 뺀 나머지'로 묶이므로 침범이 **구조적으로 불가능**해지고, 그래도 넘치면
/// 패널 안에서만 스크롤된다.
void main() {
  const topKey = Key('top-overlay');
  const handleKey = Key('hero-collapse-handle');
  const ctaKey = Key('ai-cta-row');

  /// 상단 오버레이 — 모드 세그먼트(46) + 간격(10) + 경로 입력 카드.
  Widget topOverlay() => const Padding(
        key: topKey,
        padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 46), // 모드 세그먼트
            SizedBox(height: 10),
            SizedBox(height: 96), // 경로 입력 카드(출발지·목적지)
          ],
        ),
      );

  /// 하단 패널 — 현재위치 FAB + Hero 카드(펼침) + 경로 선택 박스 + CTA.
  Widget bottomColumn({required bool withRouteSelector}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SizedBox(width: 44, height: 44),
            ),
          ),
          HeroCard(
            topHandle: Container(
                key: handleKey, height: 4, width: 36, color: Colors.grey),
            currentLevel: 25,
            isEv: false,
            reachableKm: 131,
            vehicleName: '맘카',
            efficiency: 9.5,
            tankCapacity: 55,
            fuelTypeLabel: 'LPG',
            highwayOnly: true,
            routeDistanceKm: 26, // 경로가 그려진 상태 → 도착 예상잔량 행까지 노출
            chargerMode: null,
            onTapLevel: () {},
            onTapVehicle: () {},
            onToggleHighway: () {},
          ),
          // 목적지를 넣으면 나타나는 경로 선택 박스 — 이게 붙으면서 패널이 길어진다.
          if (withRouteSelector)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(height: 130),
            ),
          const SizedBox(height: 12),
          const SizedBox(key: ctaKey, height: 54),
        ],
      );

  /// fixed=true 면 수정 후 구조(한 Column + Expanded), false 면 수정 전 구조.
  Widget screen({required bool fixed, bool withRouteSelector = true}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black12)),
            if (fixed)
              Positioned.fill(
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      topOverlay(),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: SingleChildScrollView(
                            reverse: true,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: bottomColumn(
                                  withRouteSelector: withRouteSelector),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Positioned(
                  top: 0, left: 0, right: 0, child: SafeArea(child: topOverlay())),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: bottomColumn(withRouteSelector: withRouteSelector),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void setViewport(WidgetTester tester, {double h = 640}) {
    tester.view.physicalSize = Size(380, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('수정 전 구조: 하단 패널이 상단 출발지·목적지 카드를 덮는다', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(screen(fixed: false));
    expect(tester.takeException(), isNull);

    final topBottom = tester.getBottomLeft(find.byKey(topKey)).dy;
    final panelTop = tester.getTopLeft(find.byKey(handleKey)).dy;
    // 패널 최상단이 상단 카드 아래보다 위 = 겹침(침범).
    expect(panelTop, lessThan(topBottom),
        reason: '이 기대가 깨지면 재현 조건(화면 크기·패널 구성)이 더는 겹치지 않는다는 뜻');
  });

  testWidgets('수정 후 구조: 경로 선택 박스가 붙어도 상단 카드를 침범하지 않는다', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(screen(fixed: true));
    expect(tester.takeException(), isNull);

    // ★ 위젯 좌표가 아니라 '실제로 그려지는 영역'(스크롤 뷰포트)으로 본다.
    //   스크롤뷰는 넘치는 부분을 잘라내고 안 그리므로, 내용의 기하 위치가 위로
    //   올라가 있어도 화면에 침범하지는 않는다.
    final topBottom = tester.getBottomLeft(find.byKey(topKey)).dy;
    final viewportTop =
        tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(viewportTop, greaterThanOrEqualTo(topBottom),
        reason: '하단 패널이 그려지는 영역은 상단 오버레이 아래에서 시작해야 한다');

    // 바닥의 추천 버튼은 항상 화면 안.
    expect(tester.getBottomLeft(find.byKey(ctaKey)).dy, lessThanOrEqualTo(640));
  });

  testWidgets('수정 후 구조: 넘쳐도 스크롤로 접기 핸들에 닿는다', (tester) async {
    setViewport(tester, h: 560); // 더 짧은 화면 — 확실히 넘치게
    await tester.pumpWidget(screen(fixed: true));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    final topBottom = tester.getBottomLeft(find.byKey(topKey)).dy;
    final handleTop = tester.getTopLeft(find.byKey(handleKey)).dy;
    // 스크롤해도 상단 오버레이 영역으로는 절대 올라오지 않는다.
    expect(handleTop, greaterThanOrEqualTo(topBottom));
    expect(handleTop, lessThan(560));
    expect(tester.takeException(), isNull);
  });

  testWidgets('경로 선택 박스가 없을 때(목적지 입력 전)는 예전처럼 바닥에 붙는다',
      (tester) async {
    setViewport(tester);
    await tester.pumpWidget(screen(fixed: true, withRouteSelector: false));
    expect(tester.takeException(), isNull);

    // 패널이 짧으면 그대로 바닥 정렬 — 상단과 겹치지 않고 CTA 는 화면 안.
    final topBottom = tester.getBottomLeft(find.byKey(topKey)).dy;
    expect(tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
        greaterThanOrEqualTo(topBottom));
    expect(tester.getBottomLeft(find.byKey(ctaKey)).dy, lessThanOrEqualTo(640));
  });
}
