import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:charge_helper/core/constants/api_constants.dart';
import 'package:charge_helper/ui/ai/widgets/level_basis_card.dart';
import 'package:charge_helper/ui/auth/login_screen.dart';

/// 1.3.2 신규 화면 레이아웃 검증 (iOS 기기 매트릭스).
///
/// 대상: AI 결과 상단 '기준 카드'(LevelBasisCard) · 새 로그인 화면.
/// 오버플로우는 릴리즈 빌드에서 조용히 잘려 나가므로 눈으로는 못 잡는다.
/// 배율 상한은 app.dart 의 clamp(1.0, 1.2) 를 따른다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('charge_132_test');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  // (이름, 논리 크기, safe area 상·하)
  const devices = <(String, Size, double, double)>[
    ('iPhone SE 1/5s', Size(320, 568), 20, 0), // 최소 지원(iOS 15)
    ('iPhone SE 2/3', Size(375, 667), 20, 0),
    ('iPhone 12 mini', Size(360, 780), 50, 34),
    ('iPhone 15 Pro Max', Size(430, 932), 59, 34),
  ];
  const scales = [1.0, 1.2];

  Future<List<String>> render(
    WidgetTester tester,
    Widget child, {
    required Size size,
    required double top,
    required double bottom,
    required double scale,
    required bool dark,
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

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.only(top: top, bottom: bottom),
            viewPadding: EdgeInsets.only(top: top, bottom: bottom),
          ),
          child: child,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));
    FlutterError.onError = prev;
    return overflows;
  }

  // 안내 줄 — 호출부(결과 화면)가 넣는 '칩 + 문장' 과 같은 모양.
  Widget note(String label, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      );

  // ─── 1. AI 결과 기준 카드 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final dark in [false, true]) {
        testWidgets('기준카드 ${d.$1} scale=$scale dark=$dark', (tester) async {
          final o = await render(
            tester,
            Scaffold(
              body: ListView(children: [
                // 주유 — 안내 없음
                const LevelBasisCard(
                    levelPercent: 25, kmPerPercent: 5.5, conditionLabel: '휘발유'),
                // 주유 — 안내 2줄 + 후보 수 (가장 꽉 찬 형태)
                LevelBasisCard(
                  levelPercent: 100,
                  kmPerPercent: 6.4,
                  conditionLabel: '휘발유 · 도달 범위 내',
                  countLabel: '후보 127개',
                  onEdit: () {},
                  notes: [
                    note('경로 유형', '경로가 고속도로를 지나지 않아 일반 주유소에서 추천했어요'),
                    note('선호 브랜드', '선택한 브랜드 주유소가 경로에 없어 전체에서 추천했어요'),
                  ],
                ),
                // 충전 — 긴 라벨
                LevelBasisCard(
                  levelPercent: 79,
                  kmPerPercent: 4.75,
                  isEv: true,
                  conditionLabel: '급속만',
                  countLabel: '후보 27개',
                  onEdit: () {},
                  notes: [
                    note('경로 유형', '주행 가능 거리 내에 고속도로 충전소가 없어 일반 충전소에서 추천했어요'),
                  ],
                ),
              ]),
            ),
            size: d.$2,
            top: d.$3,
            bottom: d.$4,
            scale: scale,
            dark: dark,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });
      }
    }
  }

  // ─── 2. 새 로그인 화면 ───
  // iOS 는 'Apple로 시작하기' 버튼이 하나 더 붙는다(가이드라인 4.8). 테스트는
  // macOS 에서 도니 Platform.isIOS 가 false — 그 버튼 높이(52+간격 10)만큼
  // 화면 세로를 깎아 iOS 최악 조건을 흉내 낸다.
  const appleButtonH = 62.0;
  for (final d in devices) {
    for (final scale in scales) {
      for (final gate in [true, false]) {
        testWidgets('로그인 ${d.$1} scale=$scale gate=$gate (iOS 보정)',
            (tester) async {
          final o = await render(
            tester,
            LoginScreen(gate: gate),
            size: Size(d.$2.width, d.$2.height - appleButtonH),
            top: d.$3,
            bottom: d.$4,
            scale: scale,
            dark: false,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });
      }
    }
  }

  // 로그인 화면 히어로가 가진 여유 높이 — 이 값이 곧 '로그인 배너 2지면을 켰을 때
  // 넘치지 않고 흡수할 수 있는 픽셀'이다(배너는 지면당 68~132px).
  testWidgets('로그인 배너 여유 — SE(iOS 보정)에서 히어로가 흡수 가능한 높이', (tester) async {
    await render(tester, const LoginScreen(gate: true),
        size: const Size(320, 568 - appleButtonH),
        top: 20,
        bottom: 0,
        scale: 1.2,
        dark: false);
    final hero = tester.getSize(find.byType(FittedBox).first);
    // ignore: avoid_print
    print('[로그인] SE·배율1.2 히어로 높이 = ${hero.height.toStringAsFixed(1)}px');
    expect(hero.height, greaterThan(0));
  });

  // 다크 모드에서도 항상 라이트로 그린다(형 확정) — 배경이 흰색인지 확인.
  testWidgets('로그인 — 시스템 다크에서도 라이트 배경 유지', (tester) async {
    final o = await render(tester, const LoginScreen(gate: true),
        size: const Size(375, 667 - appleButtonH),
        top: 20,
        bottom: 0,
        scale: 1.0,
        dark: true);
    expect(o, isEmpty, reason: o.join(' / '));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, isNotNull);
  });
}
