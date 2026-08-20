import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:charge_helper/core/constants/api_constants.dart';
import 'package:charge_helper/data/services/cheer_service.dart';
import 'package:charge_helper/ui/cheer/car_paint.dart';
import 'package:charge_helper/ui/cheer/car_paint_screen.dart';
import 'package:charge_helper/ui/cheer/cheer_screen.dart';
import 'package:charge_helper/ui/cheer/cheer_tier_theme.dart';
import 'package:charge_helper/ui/cheer/garage_screen.dart';
import 'package:charge_helper/ui/cheer/promotion_overlay.dart';
import 'package:charge_helper/ui/cheer/tier_detail_popup.dart';

/// 컬러 꾸미기 발견성 개선(2026-08-20) 레이아웃 검증.
///
/// 히어로 진입 pill 2개 · 최초 안내 칩 · 승급 오버레이 해금 칩 + 버튼 2단 ·
/// 개러지 꾸미기 줄 · 등급 팝업 해금 안내가 새로 붙었다. 전부 세로/가로를
/// 더 먹는 요소라, 작은 iOS 기기 × 앱 상한 텍스트 배율(app.dart cap 1.2)에서
/// 오버플로우가 없어야 한다. 릴리즈 빌드는 넘친 만큼 조용히 잘라 버린다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    // 앱 부팅과 동일하게 settings 박스를 연다 — CarPaintService 가 동기로 읽는다.
    // 박스가 없으면 coachSeen 이 안전값(true)을 내서 안내 칩이 아예 안 그려진다.
    final dir = Directory.systemTemp.createTempSync('charge_paint_test');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  setUp(() async {
    await Hive.box(AppConstants.settingsBox).clear();
  });

  // (이름, 논리 크기, safe area 상·하)
  const devices = <(String, Size, double, double)>[
    ('iPhone SE 1/5s', Size(320, 568), 20, 0), // 최소 지원(iOS 15)
    ('iPhone SE 2/3', Size(375, 667), 20, 0),
    ('iPhone 12 mini', Size(360, 780), 50, 34),
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

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.only(top: top, bottom: bottom),
        ),
        child: child,
      ),
    ));
    // 첫 프레임 + 리워드/승급 연출 구간을 지나 정지 상태까지 흘린다.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 2000));
    FlutterError.onError = prev;
    return overflows;
  }

  CheerStatus status(int total) => CheerStatus(
        today: 1,
        dailyLimit: 3,
        total: total,
        streak: 12,
        month: '2026-08',
        serverCount: 120,
        serverGoal: 300,
        serverPct: 40,
        tierAcquiredAt: const {'1': '2026-07-01', '2': '2026-07-20'},
      );

  // 등급 임계값 실측 — 보상 컬러가 걸린 2·3·4 단계를 전부 밟는다.
  final totals = <String, int>{
    '미보유': 0,
    for (final t in CheerTierTheme.tiers) t.name: t.threshold,
  };

  // ─── 1. 응원 메인 히어로 — 진입 pill 2개 + 최초 안내 칩 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final e in totals.entries) {
        testWidgets('응원화면 ${d.$1} scale=$scale ${e.key}', (tester) async {
          final o = await render(
            tester,
            CheerScreen(initialStatus: status(e.value)),
            size: d.$2,
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

  testWidgets('히어로 진입점 — 차가 있으면 꾸미기·개러지 둘 다 이름을 달고 나온다',
      (tester) async {
    await render(tester, CheerScreen(initialStatus: status(10)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    expect(find.text('내 차 꾸미기'), findsOneWidget);
    expect(find.text('내 개러지'), findsOneWidget);
    // 아직 색을 안 바꿔본 사람에겐 최초 1회 안내가 뜬다.
    expect(find.text('내 차 색을 바꿀 수 있어요'), findsOneWidget);
  });

  testWidgets('히어로 진입점 — 차가 없으면 꾸미기는 안 나온다', (tester) async {
    await render(tester, CheerScreen(initialStatus: status(0)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    expect(find.text('내 차 꾸미기'), findsNothing);
    expect(find.text('내 개러지'), findsOneWidget);
    expect(find.text('내 차 색을 바꿀 수 있어요'), findsNothing);
  });

  testWidgets('최초 안내는 닫으면 다시 안 뜬다', (tester) async {
    await render(tester, CheerScreen(initialStatus: status(10)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('내 차 색을 바꿀 수 있어요'), findsNothing);

    // 화면을 다시 그려도 Hive 플래그가 남아 안 뜬다.
    await render(tester, CheerScreen(initialStatus: status(10)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    expect(find.text('내 차 색을 바꿀 수 있어요'), findsNothing);
  });

  testWidgets('꾸미기 pill → 내 차 꾸미기 화면', (tester) async {
    await render(tester, CheerScreen(initialStatus: status(40)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    await tester.tap(find.text('내 차 꾸미기'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(CarPaintScreen), findsOneWidget);
  });

  // ─── 2. 개러지 — 꾸미기 줄 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final dark in [false, true]) {
        testWidgets('개러지 ${d.$1} scale=$scale dark=$dark', (tester) async {
          final o = await render(
            tester,
            GarageScreen(initialStatus: status(120)),
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

  testWidgets('개러지 꾸미기 줄 — 안 써본 해금 컬러 이름을 부제에 올린다', (tester) async {
    await render(tester, GarageScreen(initialStatus: status(120)),
        size: const Size(375, 667), top: 20, bottom: 0, scale: 1.0, dark: false);
    expect(find.text('내 차 꾸미기'), findsOneWidget);
    expect(find.text('「${CarPaint.black.name}」 컬러가 열려 있어요'), findsOneWidget);
  });

  // ─── 3. 승급 오버레이 — 해금 칩 + CTA 스왑 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final tier in CheerTierTheme.tiers) {
        testWidgets('승급 ${d.$1} scale=$scale ${tier.name}', (tester) async {
          final o = await render(
            tester,
            Builder(builder: (ctx) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showCheerPromotionOverlay(
                  ctx,
                  tier: tier,
                  status: status(tier.threshold),
                  onSeeGarage: () {},
                  onOpenPaint: () {},
                );
              });
              return const Scaffold(body: SizedBox.expand());
            }),
            size: d.$2,
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

  testWidgets('승급 — 보상 컬러가 있으면 해금을 알리고 주 버튼이 컬러로 간다', (tester) async {
    final tier = CheerTierTheme.byLevel(2); // 스포츠카 = 펄 화이트 해금
    await render(
      tester,
      Builder(builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showCheerPromotionOverlay(ctx,
              tier: tier,
              status: status(tier.threshold),
              onSeeGarage: () {},
              onOpenPaint: () {});
        });
        return const Scaffold(body: SizedBox.expand());
      }),
      size: const Size(375, 667),
      top: 20,
      bottom: 0,
      scale: 1.0,
      dark: false,
    );
    expect(find.text('새 컬러 「${CarPaint.pearl.name}」 해금'), findsOneWidget);
    expect(find.text('컬러 입혀보기'), findsOneWidget);
    // 개러지는 보조로 내려오되 사라지지는 않는다.
    expect(find.text('내 뱃지 보러가기'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
  });

  testWidgets('승급 — 보상 컬러가 없는 1단계는 기존 버튼 그대로', (tester) async {
    final tier = CheerTierTheme.byLevel(1);
    await render(
      tester,
      Builder(builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showCheerPromotionOverlay(ctx,
              tier: tier,
              status: status(tier.threshold),
              onSeeGarage: () {},
              onOpenPaint: () {});
        });
        return const Scaffold(body: SizedBox.expand());
      }),
      size: const Size(375, 667),
      top: 20,
      bottom: 0,
      scale: 1.0,
      dark: false,
    );
    expect(find.text('컬러 입혀보기'), findsNothing);
    expect(find.text('내 뱃지 보러가기'), findsOneWidget);
  });

  // ─── 4. 등급 상세 팝업 — 잠긴 등급 해금 티저 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final tier in CheerTierTheme.tiers) {
        testWidgets('등급팝업 ${d.$1} scale=$scale ${tier.name}', (tester) async {
          final o = await render(
            tester,
            Builder(builder: (ctx) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showTierDetailPopup(ctx,
                    tier: tier,
                    status: status(10),
                    total: 10,
                    onStatus: (_) {});
              });
              return const Scaffold(body: SizedBox.expand());
            }),
            size: d.$2,
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

  testWidgets('등급팝업 — 잠긴 등급은 함께 열리는 컬러를 미리 알려준다', (tester) async {
    await render(
      tester,
      Builder(builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showTierDetailPopup(ctx,
              tier: CheerTierTheme.byLevel(3), // 슈퍼카 = 샴페인 골드
              status: status(10),
              total: 10,
              onStatus: (_) {});
        });
        return const Scaffold(body: SizedBox.expand());
      }),
      size: const Size(375, 667),
      top: 20,
      bottom: 0,
      scale: 1.0,
      dark: false,
    );
    expect(find.text('달성하면 「${CarPaint.gold.name}」 컬러도 함께 열려요'),
        findsOneWidget);
  });

  testWidgets('등급팝업 — 보유 등급 CTA 는 다른 진입점과 같은 이름을 쓴다', (tester) async {
    await render(
      tester,
      Builder(builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showTierDetailPopup(ctx,
              tier: CheerTierTheme.byLevel(1),
              status: status(10),
              total: 10,
              onStatus: (_) {});
        });
        return const Scaffold(body: SizedBox.expand());
      }),
      size: const Size(375, 667),
      top: 20,
      bottom: 0,
      scale: 1.0,
      dark: false,
    );
    expect(find.text('내 차 꾸미기'), findsOneWidget);
    expect(find.text('컬러 꾸미기'), findsNothing);
  });

  // ─── 5. 내 차 꾸미기 화면 자체 ───
  for (final d in devices) {
    for (final scale in scales) {
      for (final tier in CheerTierTheme.tiers) {
        testWidgets('꾸미기화면 ${d.$1} scale=$scale ${tier.name}', (tester) async {
          final o = await render(
            tester,
            CarPaintScreen(tier: tier, total: tier.threshold),
            size: d.$2,
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
}
