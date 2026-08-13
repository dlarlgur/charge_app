import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:charge_helper/data/services/inbox_service.dart';
import 'package:charge_helper/ui/inbox/inbox_screen.dart';

/// 소식함 목록 행 — iPhone SE(320dp)에서 긴 제목·브랜드명이 줄을 터뜨리지 않아야 한다.
/// 앱 전역 텍스트 배율 cap 은 1.2 (lib/app.dart).
///
/// 화면(InboxScreen)이 아니라 행(InboxRow)을 그리는 이유: 화면은 initState 에서
/// 네트워크를 탄다. 행을 위젯으로 빼뒀으므로 진짜 코드를 그대로 검증한다.
void main() {
  Future<List<String>> render(WidgetTester tester, InboxItem item,
      {required bool dark, double scale = 1.2}) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exception.toString();
      if (s.contains('overflowed') || s.contains('RenderFlex')) {
        overflows.add(s.split('\n').first);
      }
    };
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(320, 568), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: InboxRow(item: item, isDark: dark),
          ),
        ),
      ),
    ));
    await tester.pump();
    FlutterError.onError = prev;
    return overflows;
  }

  const longTitle = '축하합니다! 7월의 응원왕에 뽑히셔서 치킨 기프티콘을 보내드려요';
  const longBrand = 'BBQ 황금올리브 반반세트 + 콜라 1.25L + 치즈볼';

  // 칩 문구가 상태마다 달라 폭이 바뀐다 — 가장 긴 '사용 완료'까지 전부 본다.
  final cases = <String, InboxItem>{
    '안읽음 쿠폰(D-12)': const InboxItem(
        id: 1,
        type: 'coupon',
        title: longTitle,
        couponBrand: longBrand,
        hasImage: true,
        expiresAt: '2099-12-31'),
    '사용완료 쿠폰': const InboxItem(
        id: 2,
        type: 'coupon',
        title: longTitle,
        couponBrand: longBrand,
        read: true,
        used: true,
        expiresAt: '2099-12-31'),
    '만료 쿠폰': const InboxItem(
        id: 3,
        type: 'coupon',
        title: longTitle,
        couponBrand: longBrand,
        read: true,
        expiresAt: '2000-01-01'),
    '기한없는 쿠폰': const InboxItem(
        id: 4, type: 'coupon', title: longTitle, couponBrand: longBrand),
    '일반 메시지': const InboxItem(id: 5, type: 'message', title: longTitle),
  };

  for (final e in cases.entries) {
    for (final dark in [false, true]) {
      testWidgets('소식함 행 ${e.key} dark=$dark 320dp 배율1.2', (tester) async {
        final o = await render(tester, e.value, dark: dark);
        expect(o, isEmpty, reason: o.join(' / '));
      });
    }
  }

  testWidgets('만료된 쿠폰은 D-day 대신 만료 칩', (tester) async {
    await render(tester, cases['만료 쿠폰']!, dark: false);
    expect(find.text('만료'), findsOneWidget);
    expect(find.textContaining('D-'), findsNothing);
  });

  testWidgets('사용 완료가 만료보다 우선 표시된다', (tester) async {
    await render(tester, cases['사용완료 쿠폰']!, dark: false);
    expect(find.text('사용 완료'), findsOneWidget);
  });

  testWidgets('일반 메시지엔 칩이 없다', (tester) async {
    await render(tester, cases['일반 메시지']!, dark: false);
    expect(find.text('쿠폰'), findsNothing);
    expect(find.textContaining('D-'), findsNothing);
  });
}
