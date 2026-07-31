import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:charge_helper/ui/ai/widgets/savings_share_card.dart';
import 'package:charge_helper/ui/ai/widgets/savings_reveal_overlay.dart';

/// 공유 카드는 고정 크기(360×450 / 360×640)로 캡처된다. 한 줄만 넘쳐도
/// 결과 이미지에 노란 줄무늬가 박히므로, 조합 전부를 그려 예외가 없는지 본다.
void main() {
  const facts = <RevealFact>[
    (label: '유종', value: '휘발유'),
    (label: '리터당 단가', value: '1,824원/L'),
    (label: '주변 평균 대비', value: '▼32원/L'),
    (label: '주변 평균가', value: '1,856원/L'),
    (label: '주유량', value: '33.8L'),
    (label: '거리', value: '경로에서 1.2km'),
    (label: '예상 주유비', value: '61,665원'),
    (label: '추가 시간', value: '+9분'),
  ];

  for (final style in ShareCardStyle.values) {
    for (final story in [false, true]) {
      for (final isEv in [false, true]) {
        testWidgets('$style story=$story ev=$isEv 오버플로우 없음',
            (tester) async {
          tester.view.physicalSize = const Size(1200, 2000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Center(
                child: SavingsShareCard(
                  caption: '주변 평균 대비 · 휘발유',
                  headline: '1,068원 절약!',
                  isEv: isEv,
                  stationName: '㈜버드에너지 광주제일주유소',
                  stationSub: '휘발유 · SK에너지 · 경기 광주시 오포읍 양벌로 55',
                  facts: facts,
                  story: story,
                  style: style,
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
