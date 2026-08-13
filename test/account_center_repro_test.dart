import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:charge_helper/ui/cheer/gold_profile.dart';

/// 계정 관리 프로필 카드 가운데 정렬 — **실제 위젯**을 그려서 좌표로 잰다.
///
/// 형이 "중앙정렬 안 된다"고 한 게 여기다. 원인은 닉네임 옆 연필 아이콘이었다:
/// [이름 + 6 + 아이콘15] 묶음을 Column 이 가운데 놓으면 묶음은 중앙이지만
/// **이름 자체는 10.5px 왼쪽**으로 밀린다. 바로 아래 이메일은 정중앙이라
/// 둘이 어긋나 보인다. 왼쪽에 같은 폭을 비워 이름을 실제 중앙에 오게 했다.
void main() {
  const cardW = 328.0; // 360dp 화면에서 좌우 패딩 16 뺀 카드 폭

  Future<void> pump(WidgetTester tester,
      {required String nickname,
      required String email,
      String? ageGroup,
      bool dark = false,
      double scale = 1.0}) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(360, 720), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: cardW,
              child: BrandProfileCard(
                isDark: dark,
                nickname: nickname,
                email: email,
                ageGroup: ageGroup,
                // 실제 화면은 사진 변경 시트를 감싸지만, 정렬 검증엔 아바타 본체면 된다.
                avatar: GoldAvatar(size: 64, isDark: dark, cameraBadge: true),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// 카드 중앙과 각 요소 중앙이 같은지. 허용 오차 1px.
  void expectCentered(WidgetTester tester, Finder f, String label) {
    final x = tester.getCenter(f).dx;
    expect(x, closeTo(cardW / 2, 1.0), reason: '$label 중심 x=$x (기대 ${cardW / 2})');
  }

  testWidgets('닉네임·이메일·아바타가 모두 카드 정중앙', (tester) async {
    await pump(tester,
        nickname: '임건식님', email: 'a01035048300@gmail.com');
    expectCentered(tester, find.text('임건식님'), '닉네임');
    expectCentered(tester, find.text('a01035048300@gmail.com'), '이메일');
    expectCentered(tester, find.byType(GoldAvatar), '아바타');
  });

  testWidgets('닉네임이 이메일과 같은 축에 있다 (연필이 밀지 않는다)', (tester) async {
    await pump(tester, nickname: '동키파파님', email: 'ghim2131@gmail.com');
    final nick = tester.getCenter(find.text('동키파파님')).dx;
    final mail = tester.getCenter(find.text('ghim2131@gmail.com')).dx;
    expect((nick - mail).abs(), lessThan(1.0),
        reason: '닉네임 x=$nick / 이메일 x=$mail — 어긋나면 연필이 이름을 민 것');
  });

  testWidgets('짧은 닉네임에서도 중앙 (묶음 중앙 ≠ 이름 중앙 회귀)', (tester) async {
    await pump(tester, nickname: '김님', email: 'a@b.com');
    expectCentered(tester, find.text('김님'), '짧은 닉네임');
  });

  testWidgets('연령대 칩이 있어도 중앙', (tester) async {
    await pump(tester,
        nickname: '임건식님', email: 'a@b.com', ageGroup: '60대이상');
    expectCentered(tester, find.text('임건식님'), '닉네임');
    expectCentered(tester, find.text('60대이상'), '연령대 칩');
  });

  testWidgets('다크 모드에서도 중앙', (tester) async {
    await pump(tester,
        nickname: '임건식님', email: 'a01035048300@gmail.com', dark: true);
    expectCentered(tester, find.text('임건식님'), '닉네임(다크)');
  });

  testWidgets('텍스트 배율 1.2 에서도 중앙 + 오버플로우 없음', (tester) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception.toString().contains('overflowed')) {
        overflows.add(d.exception.toString().split('\n').first);
      }
    };
    await pump(tester,
        nickname: '아주긴닉네임을쓰는사람님',
        email: 'verylongemailaddress@example.com',
        ageGroup: '60대이상',
        scale: 1.2);
    FlutterError.onError = prev;
    expect(overflows, isEmpty, reason: overflows.join(' / '));
    expectCentered(tester, find.byType(GoldAvatar), '아바타(배율1.2)');
  });
}
