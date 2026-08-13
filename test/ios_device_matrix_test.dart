import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:charge_helper/data/services/cheer_service.dart';
import 'package:charge_helper/data/services/inbox_service.dart';
import 'package:charge_helper/ui/cheer/awards_screen.dart';
import 'package:charge_helper/ui/cheer/cheer_entry_card.dart';
import 'package:charge_helper/ui/cheer/gold_profile.dart';
import 'package:charge_helper/ui/inbox/inbox_screen.dart';

/// 1.3.0 릴리즈 전 iOS 기기 전수 검증.
///
/// 실제 iOS 논리 해상도로 새 화면을 전부 그려 오버플로우가 없는지 본다.
/// 오버플로우는 릴리즈 빌드에서 **조용히 잘려 나가므로** 눈으로는 못 잡는다.
/// 노치/홈 인디케이터가 있는 기기는 SafeArea 가 세로를 더 먹으므로 padding 도 준다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // (이름, 논리 크기, safe area 상·하)
  const devices = <(String, Size, double, double)>[
    ('iPhone SE 1/5s', Size(320, 568), 20, 0), // 최소 지원(iOS 15)
    ('iPhone SE 2/3', Size(375, 667), 20, 0),
    ('iPhone 12 mini', Size(360, 780), 50, 34),
    ('iPhone 14/15', Size(390, 844), 47, 34),
    ('iPhone 15 Pro Max', Size(430, 932), 59, 34),
    ('iPad mini(분할)', Size(744, 1133), 24, 20),
  ];

  Future<List<String>> render(
    WidgetTester tester,
    Widget child, {
    required Size size,
    required double top,
    required double bottom,
    required double scale,
    required bool dark,
    bool fullScreen = false,
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
          viewPadding: EdgeInsets.only(top: top, bottom: bottom),
        ),
        child: fullScreen
            ? child
            : Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: child)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 2600));
    FlutterError.onError = prev;
    return overflows;
  }

  CheerAwards awards({bool chicken = true, bool sent = false}) => CheerAwards(
        month: '2026-07',
        total: 128450,
        top: const [
          CheerAwardRank(rank: 1, name: '전기차타는사람', count: 93, me: false),
          CheerAwardRank(rank: 2, name: '기름값아끼는사람', count: 88, me: false),
          CheerAwardRank(rank: 3, name: '충전소순례자', count: 81, me: false),
        ],
        myRank: 27,
        myCount: 42,
        delta: 12,
        winner: true,
        chickenOn: chicken,
        chickenSent: sent,
        chickenInboxId: sent ? 41 : null,
      );

  // 앱 전역 텍스트 배율 cap 은 1.2 (lib/app.dart)
  for (final (name, size, top, bottom) in devices) {
    for (final scale in [1.0, 1.2]) {
      for (final dark in [false, true]) {
        final tag = '$name ${size.width.toInt()}x${size.height.toInt()} '
            'scale=$scale dark=$dark';

        testWidgets('시상식 · $tag', (tester) async {
          final o = await render(tester,
              AwardsScreen(data: awards(), nickname: '전기차타는김대리님입니다'),
              size: size,
              top: top,
              bottom: bottom,
              scale: scale,
              dark: dark,
              fullScreen: true);
          expect(o, isEmpty, reason: o.join(' / '));
        });

        testWidgets('시상식(치킨 도착) · $tag', (tester) async {
          final o = await render(tester,
              AwardsScreen(data: awards(sent: true), nickname: '전기차왕'),
              size: size,
              top: top,
              bottom: bottom,
              scale: scale,
              dark: dark,
              fullScreen: true);
          expect(o, isEmpty, reason: o.join(' / '));
        });

        testWidgets('프로필 카드 · $tag', (tester) async {
          final o = await render(
            tester,
            BrandProfileCard(
              isDark: dark,
              nickname: '전기차타는김대리님입니다',
              email: 'verylongemailaddress@example.com',
              ageGroup: '60대이상',
              avatar: GoldAvatar(
                  size: 108, ringWidth: 3, badgeSize: 34, isDark: dark, cameraBadge: true),
            ),
            size: size,
            top: top,
            bottom: bottom,
            scale: scale,
            dark: dark,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });

        testWidgets('응원 진입 카드 · $tag', (tester) async {
          final o = await render(tester, const CheerEntryCard(),
              size: size, top: top, bottom: bottom, scale: scale, dark: dark);
          expect(o, isEmpty, reason: o.join(' / '));
        });

        testWidgets('소식함 행 · $tag', (tester) async {
          final o = await render(
            tester,
            InboxRow(
              isDark: dark,
              item: const InboxItem(
                id: 1,
                type: 'coupon',
                title: '축하합니다! 7월의 응원왕에 뽑히셔서 치킨 기프티콘을 보내드려요',
                couponBrand: 'BBQ 황금올리브 반반세트 + 콜라 1.25L',
                hasImage: true,
                expiresAt: '2099-12-31',
              ),
            ),
            size: size,
            top: top,
            bottom: bottom,
            scale: scale,
            dark: dark,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });

        testWidgets('수상 메달 · $tag', (tester) async {
          final o = await render(
            tester,
            AwardMedals(isDark: dark, items: const [
              (rank: 1, label: '8월 1위'),
              (rank: 2, label: '7월 2위'),
              (rank: 3, label: '6월 3위'),
            ]),
            size: size,
            top: top,
            bottom: bottom,
            scale: scale,
            dark: dark,
          );
          expect(o, isEmpty, reason: o.join(' / '));
        });
      }
    }
  }

  // 시상식 CTA 두 개는 **화면 안에 있어야** 한다 — 잘리면 공유도 이동도 못 한다.
  for (final (name, size, top, bottom) in devices) {
    testWidgets('시상식 CTA 가 화면 안에 있다 · $name', (tester) async {
      await render(tester, AwardsScreen(data: awards(), nickname: '전기차왕'),
          size: size,
          top: top,
          bottom: bottom,
          scale: 1.2,
          dark: false,
          fullScreen: true);
      for (final label in ['수상 결과 공유', '8월 응원 시작하기']) {
        final f = find.text(label);
        expect(f, findsOneWidget, reason: '$label 이 없다');
        final r = tester.getRect(f);
        expect(r.bottom, lessThanOrEqualTo(size.height),
            reason: '$label 이 화면 아래로 잘림 (bottom=${r.bottom} > ${size.height})');
        expect(r.top, greaterThanOrEqualTo(0), reason: '$label 이 위로 잘림');
      }
    });
  }
}
