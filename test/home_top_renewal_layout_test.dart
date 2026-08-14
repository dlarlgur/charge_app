import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // RenderParagraph
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:charge_helper/core/theme/app_theme.dart';
import 'package:charge_helper/data/services/cheer_service.dart';
import 'package:charge_helper/data/services/api_service.dart' show shortRegionName;
import 'package:charge_helper/ui/home/cheer_strip.dart';
import 'package:charge_helper/ui/home/home_top_header.dart';
import 'package:charge_helper/ui/home/report_fab.dart';

/// 홈 상단 리뉴얼(handoff `design_handoff_home_top_renewal 2`) 전수 검증.
///
/// 실제 Pretendard 를 FontLoader 로 물려서 잰다 — 테스트 기본 폰트는 모든 글리프
/// 폭이 fontSize 라서 공백까지 한 글자 폭으로 잡혀 실제보다 넓게 나온다.
/// 오버플로우뿐 아니라 **말줄임(ellipsis)** 도 실패로 본다. maxLines:1 + ellipsis 는
/// 오버플로우 경고 없이 조용히 잘리므로 눈으로도 테스트로도 안 잡히는 자리다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      try {
        final loader = FontLoader('Pretendard')
          ..addFont(rootBundle.load('assets/fonts/Pretendard-$w.otf'));
        await loader.load();
      } catch (_) {/* 해당 weight 미번들 */}
    }
    Hive.init('${Directory.systemTemp.path}/charge_test_hive');
    await Hive.openBox('settings');
  });

  // (이름, 논리 크기) — iOS 최소~최대 + iPad
  const devices = <(String, Size)>[
    ('iPhone SE 1/5s', Size(320, 568)),
    ('iPhone 12 mini', Size(360, 780)),
    ('iPhone SE 2/3', Size(375, 667)),
    ('iPhone 14/15', Size(390, 844)),
    ('iPhone 15 Pro Max', Size(430, 932)),
    ('iPad mini(분할)', Size(744, 1133)),
    ('iPad Pro 12.9', Size(1024, 1366)),
  ];

  /// 화면 폭·텍스트 스케일 고정 렌더. 반환 = 오버플로우 메시지 목록.
  Future<List<String>> render(
    WidgetTester tester,
    Widget child, {
    required Size size,
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
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 47, bottom: 34),
        ),
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [child, const Expanded(child: SizedBox())]),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    FlutterError.onError = prev;
    return overflows;
  }

  /// 화면에 그려진 `text` 가 말줄임 됐는지 (maxLines 초과).
  bool truncated(WidgetTester tester, String text) {
    final el = find.text(text);
    if (el.evaluate().isEmpty) return false;
    final rp = tester.renderObject<RenderParagraph>(el.first);
    return rp.didExceedMaxLines;
  }

  Widget header(String? region, {bool showTabs = true}) => HomeTopHeader(
        activeIndex: 0,
        onChanged: (_) {},
        showTabs: showTabs,
        regionName: region,
        hasUnread: true,
        onBellTap: () {},
        onRegionTap: (_) {},
      );

  CheerStatus status({int today = 0, int limit = 3}) => CheerStatus(
        today: today,
        dailyLimit: limit,
        total: 42,
        streak: 3,
        month: '2026-08',
        serverCount: 100,
        serverGoal: 300,
        serverPct: 33,
      );

  // ── 1. 한 줄 헤더 ────────────────────────────────────────────────
  group('HomeTopHeader', () {
    for (final (name, size) in devices) {
      for (final scale in [1.0, 1.2]) {
        for (final dark in [false, true]) {
          testWidgets('$name x$scale ${dark ? 'dark' : 'light'}',
              (tester) async {
            final o = await render(tester, header('정자동'),
                size: size, scale: scale, dark: dark);
            expect(o, isEmpty, reason: '$name x$scale 오버플로우');
            expect(truncated(tester, '정자동'), isFalse,
                reason: '$name x$scale 지역명 말줄임');
            expect(truncated(tester, '주유'), isFalse);
            expect(truncated(tester, '충전'), isFalse);
          });
        }
      }
    }

    testWidgets('긴 동 이름 — 최소 기기 x1.2', (tester) async {
      // 실제로 존재하는 긴 행정동들
      for (final region in ['상계제3.4동', '금호1가동', '용현1.4동', '신정제7동']) {
        final o = await render(tester, header(region),
            size: const Size(320, 568), scale: 1.2, dark: false);
        expect(o, isEmpty, reason: '$region 오버플로우');
        // 말줄임은 스펙상 허용(`길면 ellipsis`) — 몇 글자가 남는지만 기록
        // ignore: avoid_print
        print('  $region → 말줄임 ${truncated(tester, region) ? "O" : "X"}');
      }
    });

    testWidgets('탭 숨김(차량 타입 단일) — 지역명이 왼쪽', (tester) async {
      final o = await render(tester, header('정자동', showTabs: false),
          size: const Size(320, 568), scale: 1.2, dark: false);
      expect(o, isEmpty);
    });

    testWidgets('지역명 null(역지오코딩 실패) — 로고만', (tester) async {
      final o = await render(tester, header(null),
          size: const Size(320, 568), scale: 1.2, dark: false);
      expect(o, isEmpty);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    });

    testWidgets('헤더 높이 — 기존 대비 절감 확인', (tester) async {
      await render(tester, header('정자동'),
          size: const Size(390, 844), scale: 1.0, dark: false);
      final h = tester.getSize(find.byType(HomeTopHeader)).height;
      // ignore: avoid_print
      print('  헤더 높이 x1.0 = $h');
      expect(h, lessThan(70));
    });

    testWidgets('탭 터치 영역 46 이상 (스펙 규칙 2)', (tester) async {
      await render(tester, header('정자동'),
          size: const Size(390, 844), scale: 1.0, dark: false);
      final tap = find.ancestor(
          of: find.text('주유'), matching: find.byType(GestureDetector));
      final box = tester.getSize(tap.first);
      // ignore: avoid_print
      print('  주유 탭 터치 영역 = $box');
      expect(box.height, greaterThanOrEqualTo(46));
    });

    // 회귀 — 언더바가 글자에 달라붙어 '밑줄'처럼 보였다(형 지적, 두 번).
    // 원인은 언더바 위치가 아니라 글자 스타일에 `height: 1.0` 이 없던 것:
    // Pretendard 기본 행높이(≈1.27)로 글자 박스가 28 까지 부풀어, 46 안에서
    // 언더바를 바닥에 붙여도 3~4 밖에 안 남았다. 스펙 §2-1-1 고정값을 박아둔다.
    //
    // x1.0 에서만 잰다 — 글자 박스는 배율을 따라 커지는데 46 박스는 안 커지므로
    // 큰 글씨 설정에서는 간격이 줄어드는 게 정상이다.
    testWidgets('언더바 — 글자 박스 하단과 9, 길이는 글자 폭 + 좌우 7 (스펙 §2-1-1)',
        (tester) async {
      await render(tester, header('정자동'),
          size: const Size(390, 844), scale: 1.0, dark: false);

      final stack =
          find.ancestor(of: find.text('주유'), matching: find.byType(Stack)).first;
      final bar =
          find.descendant(of: stack, matching: find.byType(AnimatedContainer)).first;
      final textRect = tester.getRect(find.text('주유'));
      final barRect = tester.getRect(bar);

      // ignore: avoid_print
      print('  글자 박스 ${textRect.height} / 간격 ${barRect.top - textRect.bottom}'
          ' / 언더바 폭 ${barRect.width} (글자 ${textRect.width})');

      expect(textRect.height, closeTo(22, 0.5), reason: 'height:1.0 이 빠졌다');
      expect(barRect.top - textRect.bottom, closeTo(9, 0.5), reason: '언더바 간격');
      expect(barRect.width - textRect.width, closeTo(14, 0.5),
          reason: '언더바는 글자 폭 + 좌우 7');
      expect(barRect.height, closeTo(3, 0.01));
    });
  });

  // ── 2. 응원 스트립 ──────────────────────────────────────────────
  group('CheerStrip', () {
    for (final (name, size) in devices) {
      for (final scale in [1.0, 1.2]) {
        testWidgets('$name x$scale — 문구 한 줄에 다 들어가는가', (tester) async {
          CheerService.instance.statusNotifier.value = status();
          final o = await render(tester, const CheerStrip(),
              size: size, scale: scale, dark: false);
          expect(o, isEmpty, reason: '$name x$scale 오버플로우');
          expect(truncated(tester, CheerStrip.kMessage), isFalse,
              reason: '$name x$scale 응원 문구 말줄임 — '
                  '"${CheerStrip.kMessage}" 가 잘린다');
        });
      }
    }

    testWidgets('오늘 한도 소진 상태 — 최소 기기 x1.2', (tester) async {
      CheerService.instance.statusNotifier.value = status(today: 3);
      final o = await render(tester, const CheerStrip(),
          size: const Size(320, 568), scale: 1.2, dark: false);
      expect(o, isEmpty);
      expect(truncated(tester, CheerStrip.kDoneMessage), isFalse,
          reason: '완료 문구 말줄임');
    });

    testWidgets('status 미도착(콜드스타트) — 최소 기기 x1.2', (tester) async {
      CheerService.instance.statusNotifier.value = null;
      final o = await render(tester, const CheerStrip(),
          size: const Size(320, 568), scale: 1.2, dark: false);
      expect(o, isEmpty);
      expect(truncated(tester, CheerStrip.kMessage), isFalse);
    });

    // 회귀 — 오늘 3/3 을 채운 사람이 홈에 들어오면 '응원' 버튼이 먼저 떴다가
    // status 응답 순간 '오늘 만땅!' 으로 획 바뀌었다(형 제보). 캐시를 보고
    // **첫 프레임부터** 완료 상태로 그려야 한다.
    String kstDay([int offsetDays = 0]) {
      final d = DateTime.now().toUtc().add(Duration(hours: 9 - 24 * offsetDays));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}'
          '-${d.day.toString().padLeft(2, '0')}';
    }

    Future<void> putDaily(String day, int today, int limit) async {
      final box = Hive.box('settings');
      await box.put('cheer_daily_day', day);
      await box.put('cheer_daily_today', today);
      await box.put('cheer_daily_limit', limit);
    }

    testWidgets('콜드스타트 + 오늘 한도 소진 캐시 — 깜빡임 없이 바로 완료 문구',
        (tester) async {
      await putDaily(kstDay(), 3, 3);
      CheerService.instance.statusNotifier.value = null;
      await render(tester, const CheerStrip(),
          size: const Size(390, 844), scale: 1.0, dark: false);
      expect(find.text(CheerStrip.kDoneMessage), findsOneWidget);
      expect(find.text(CheerStrip.kMessage), findsNothing);
    });

    testWidgets('캐시가 어제 것이면 오늘은 0 으로 본다', (tester) async {
      await putDaily(kstDay(1), 3, 3); // 어제 만땅
      CheerService.instance.statusNotifier.value = null;
      await render(tester, const CheerStrip(),
          size: const Size(390, 844), scale: 1.0, dark: false);
      expect(find.text(CheerStrip.kMessage), findsOneWidget,
          reason: '날짜가 바뀌었는데 어제 만땅이 오늘로 새어나왔다');
      await Hive.box('settings').delete('cheer_daily_day');
    });
  });

  // ── 3. 퀵메뉴 — 응원 항목(NEW 배지) ────────────────────────────
  group('HomeQuickFab', () {
    for (final (name, size) in [devices.first, devices[3], devices.last]) {
      for (final scale in [1.0, 1.2]) {
        testWidgets('$name x$scale — 메뉴 펼침', (tester) async {
          final o = await render(
            tester,
            SizedBox(
              height: 400,
              child: Align(
                alignment: Alignment.bottomRight,
                child: HomeQuickFab(items: [
                  QuickMenuItem(
                      icon: Icons.volunteer_activism_rounded,
                      label: '개발자 응원하기',
                      color: const Color(0xFFF59E0B),
                      highlight: true,
                      onTap: () {}),
                  QuickMenuItem(
                      icon: Icons.notifications_active_rounded,
                      label: '가격 알림 설정',
                      color: const Color(0xFF3B82F6),
                      badge: 3,
                      onTap: () {}),
                  QuickMenuItem(
                      icon: Icons.my_location_rounded,
                      label: '현재 위치로 재검색',
                      color: const Color(0xFF3B82F6),
                      onTap: () {}),
                ]),
              ),
            ),
            size: size,
            scale: scale,
            dark: false,
          );
          expect(o, isEmpty, reason: '접힌 FAB $name x$scale');

          await tester.tap(find.byType(HomeQuickFab));
          await tester.pumpAndSettle();
          expect(find.text('개발자 응원하기'), findsOneWidget);
          // NEW 배지는 뺐다 — 끌 조건이 없으면 영구히 붙어 거짓 배지가 된다(형 결정).
          expect(find.text('NEW'), findsNothing);
          expect(truncated(tester, '개발자 응원하기'), isFalse,
              reason: '$name x$scale 메뉴 라벨 말줄임');
          expect(truncated(tester, '현재 위치로 재검색'), isFalse,
              reason: '$name x$scale 메뉴 라벨 말줄임');
        });
      }
    }
  });

  // ── 4. shortRegionName 단위 ─────────────────────────────────────
  group('shortRegionName', () {
    test('행정동만 남긴다', () {
      expect(shortRegionName('경기도 성남시 분당구 정자동'), '정자동');
      expect(shortRegionName('서울특별시 성동구 금호동1가'), '금호동1가');
      expect(shortRegionName('강원특별자치도 양양군 현남면'), '현남면');
      expect(shortRegionName('제주특별자치도 제주시 애월읍'), '애월읍');
      expect(shortRegionName(null), isNull);
      expect(shortRegionName('   '), isNull);
    });
    test('동/읍/면 이 없으면 구/군/시 로 물러선다', () {
      expect(shortRegionName('서울특별시 종로구'), '종로구');
    });
    // 실서버 회귀 — 카카오·네이버 모두 도로명주소를 우선 반환한다.
    // 예전 구현은 마지막 토큰을 그대로 써서 헤더에 '6' / '110' 이 떴다.
    test('도로명주소의 건물번호를 지역명으로 내놓지 않는다', () {
      expect(shortRegionName('경기도 성남시 분당구 불정로 6'), '분당구');
      expect(shortRegionName('서울특별시 중구 세종대로 110'), '중구');
      expect(shortRegionName('불정로 6'), isNull);
    });
  });
}
