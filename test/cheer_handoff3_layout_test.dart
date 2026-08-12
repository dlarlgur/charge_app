import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:charge_helper/data/services/cheer_service.dart';
import 'package:charge_helper/ui/cheer/awards_screen.dart';
import 'package:charge_helper/ui/cheer/cheer_entry_card.dart';
import 'package:charge_helper/ui/cheer/gold_profile.dart';

/// handoff 3 화면들 — 작은 iOS 기기(iPhone SE 320×568 / SE3 375×667)에서
/// 텍스트 스케일 최대치(app.dart 가 1.2 로 cap)까지 올려도 레이아웃이 깨지지
/// 않는지 본다. 오버플로우는 릴리즈 빌드에서 조용히 잘려 나가므로 테스트로만 잡힌다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  /// 화면 크기 · 텍스트 스케일을 고정해 위젯을 그린다.
  Future<List<String>> render(
    WidgetTester tester,
    Widget child, {
    required Size size,
    required double scale,
    required bool dark,
    bool fullScreen = false,
    EdgeInsets contentPadding = const EdgeInsets.all(16),
  }) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exception.toString();
      if (s.contains('overflowed') || s.contains('RenderFlex')) {
        overflows.add(s.split('\n').first);
      }
    };
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 20),
        ),
        child: fullScreen
            ? child
            : Scaffold(
                body: SingleChildScrollView(
                    padding: contentPadding, child: child)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 2600));
    FlutterError.onError = prev;
    return overflows;
  }

  const sizes = {
    'SE1 320x568': Size(320, 568),
    'SE3 375x667': Size(375, 667),
  };

  // ─── 1. 설정 진입 카드 ───
  for (final e in sizes.entries) {
    for (final scale in [1.0, 1.2]) {
      for (final dark in [false, true]) {
        testWidgets('진입카드 ${e.key} scale=$scale dark=$dark', (tester) async {
          final o = await render(tester, const CheerEntryCard(),
              size: e.value, scale: scale, dark: dark);
          expect(o, isEmpty, reason: o.join(' / '));
        });
      }
    }
  }

  // 하루 한도는 원격설정(cheer.daily_limit)으로 앱 배포 없이 바뀐다 —
  // 도트가 한도만큼 늘어나므로 큰 값에서도 320dp 를 넘지 않아야 한다.
  for (final limit in [3, 5, 10, 20]) {
    testWidgets('진입카드 dailyLimit=$limit 320dp', (tester) async {
      CheerService.instance.lastStatus = CheerStatus(
        today: limit,
        dailyLimit: limit,
        total: 137,
        streak: 4,
        month: '2026-08',
        serverCount: 120,
        serverGoal: 300,
        serverPct: 40,
      );
      addTearDown(() => CheerService.instance.lastStatus = null);
      final o = await render(tester, const CheerEntryCard(),
          size: const Size(320, 568), scale: 1.2, dark: false);
      expect(o, isEmpty, reason: o.join(' / '));
    });
  }

  // ─── 2. 시상식 모달 (전체 화면) ───
  CheerAwards awards({
    bool chicken = false,
    bool meInTop = true,
    int? myRank = 1,
    String name = '전기차왕',
  }) =>
      CheerAwards(
        month: '2026-07',
        total: 128450,
        top: [
          CheerAwardRank(rank: 1, name: name, count: 93, me: meInTop),
          const CheerAwardRank(
              rank: 2, name: '기름값아끼는사람', count: 88, me: false),
          const CheerAwardRank(rank: 3, name: '충전소순례자', count: 81, me: false),
        ],
        myRank: myRank,
        myCount: 42,
        delta: 12,
        winner: true,
        chickenOn: chicken,
        chickenSent: false,
      );

  for (final e in sizes.entries) {
    for (final scale in [1.0, 1.2]) {
      for (final chicken in [false, true]) {
        testWidgets('시상식 ${e.key} scale=$scale chicken=$chicken',
            (tester) async {
          final o = await render(
            tester,
            AwardsScreen(
                data: awards(chicken: chicken, meInTop: false, myRank: 27),
                nickname: '전기차타는김대리님입니다'),
            size: e.value,
            scale: scale,
            dark: false,
            fullScreen: true,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });
      }
    }
  }

  testWidgets('시상식 비회원 1등 — 기기 별칭 + 로그인 필요 배너', (tester) async {
    final o = await render(
      tester,
      AwardsScreen(
          data: awards(chicken: true, name: '응원자 4821'),
          nickname: '응원자 4821',
          loggedIn: false),
      size: const Size(320, 568),
      scale: 1.2,
      dark: false,
      fullScreen: true,
    );
    expect(o, isEmpty, reason: o.join(' / '));
  });

  testWidgets('시상식 다크 + 내가 1위(내 순위 줄 없음)', (tester) async {
    final o = await render(tester,
        AwardsScreen(data: awards(chicken: true), nickname: '전기차왕'),
        size: const Size(320, 568),
        scale: 1.2,
        dark: true,
        fullScreen: true);
    expect(o, isEmpty, reason: o.join(' / '));
  });

  // ─── 3. 공유 이미지 카드 (고정 270×337.5, 텍스트 스케일 무시) ───
  for (final dark in [false, true]) {
    for (final long in [false, true]) {
      testWidgets('공유카드 dark=$dark long=$long', (tester) async {
        final o = await render(
          tester,
          Center(
            child: SizedBox(
              width: AwardsShare.cardW,
              height: AwardsShare.cardH,
              child: CertificateCard(
                anim: kAlwaysDismissedAnimation,
                isDark: dark,
                title: '2026년 7월의 응원왕',
                name: long ? '전기차타는김대리님입니다반갑습니다' : '전기차왕',
                count: long ? 9999 : 93,
                footer: CertificateFooter.share,
                chicken: true,
                radius: 20,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              ),
            ),
          ),
          size: const Size(375, 667),
          // 공유 PNG 는 AwardsShare._render 가 textScaler.noScaling 으로 그린다 —
          // 시스템 폰트 크기와 무관하게 항상 1.0.
          scale: 1.0,
          dark: dark,
        );
        expect(o, isEmpty, reason: o.join(' / '));
      });
    }
  }

  // ─── 3-1. 수상 메달 줄 — 개수가 1·2개여도 가운데 정렬이어야 한다 ───
  for (final n in [1, 2, 3]) {
    testWidgets('수상 메달 $n개 가운데 정렬', (tester) async {
      const w = 300.0;
      final o = await render(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: AwardMedals(
              isDark: false,
              items: [
                for (var r = 1; r <= n; r++) (rank: r, label: '8월 $r위'),
              ],
            ),
          ),
        ),
        size: const Size(375, 667),
        scale: 1.0,
        dark: false,
        contentPadding: EdgeInsets.zero,
      );
      expect(o, isEmpty, reason: o.join(' / '));

      // 메달 숫자 텍스트의 좌우 끝 중점이 컨테이너 정중앙이어야 한다.
      final xs = [
        for (var r = 1; r <= n; r++) tester.getCenter(find.text('$r')).dx,
      ];
      expect((xs.first + xs.last) / 2, closeTo(w / 2, 0.5),
          reason: '메달 $n개 중심 x=$xs');
    });
  }

  // ─── 4. 골드 아바타 (링 두께 비율) ───
  testWidgets('골드 아바타 56/64 렌더', (tester) async {
    final o = await render(
      tester,
      const Row(children: [
        GoldAvatar(size: 56, isDark: false),
        GoldAvatar(size: 64, isDark: true, cameraBadge: true),
      ]),
      size: const Size(320, 568),
      scale: 1.2,
      dark: false,
    );
    expect(o, isEmpty, reason: o.join(' / '));
  });
}
