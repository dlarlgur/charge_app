import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:charge_helper/core/constants/api_constants.dart';
import 'package:charge_helper/ui/ai/ai_result_screen.dart';

/// 결과 시트가 "내용 없이 흰 화면"으로 뜬다는 제보(형 2026-08-19) 분리 테스트.
///
/// 팝업(보상 카드)에는 추천이 정상적으로 떴으므로 응답 데이터는 멀쩡하다.
/// 그렇다면 남는 건 ① AiResultBody 자체가 못 그리는가 ② 그리는데 시트가
/// 안 보여주는가 — 이 테스트는 ①을 배제하기 위한 것이다.
///
/// fixture 는 실제 운영 서버(charge.dksw4.com) 응답:
///   수내역 수인분당선 → 서울중구청 / LPG(K015) / 55L / 9.5km/L / 잔량 25% / 고속도로 필터 ON
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 앱 부팅과 동일하게 settings 박스를 연다 (단골 등 위젯이 동기로 읽는다).
    final dir = Directory.systemTemp.createTempSync('charge_hive_test');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox('station_aliases');
  });

  final raw = File('test/fixtures/refuel_analyze_lpg_highway.json')
      .readAsStringSync();

  Map<String, dynamic> load() =>
      Map<String, dynamic>.from(jsonDecode(raw) as Map);

  Future<void> pumpSheet(WidgetTester tester, Map<String, dynamic> data) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black12)),
            // 실제 화면과 같은 구성: DraggableScrollableSheet 가 준 컨트롤러를
            // AiResultBody 의 CustomScrollView 에 연결한다.
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.12, 0.45, 0.9],
              builder: (_, sc) => ColoredBox(
                color: Colors.white,
                child: AiResultBody(
                  data: data,
                  destinationName: '서울중구청',
                  originLat: 37.3784687674046,
                  originLng: 127.114288846291,
                  scrollController: sc,
                  fuelLabel: 'LPG',
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('실서버 응답(고속도로 폴백) — 시트에 추천 카드가 그려진다', (tester) async {
    final data = load();
    await pumpSheet(tester, data);

    expect(tester.takeException(), isNull);
    // 추천 주유소 이름이 실제로 화면에 붙었는지 (빈 시트면 여기서 죽는다)
    final name = (data['best_detour']['station']['name'] as String);
    expect(find.textContaining(name.substring(0, 6)), findsWidgets);
  });

  testWidgets('고속도로 필터 applied=true — 안내 배너 + 재조회 버튼이 그려진다',
      (tester) async {
    final data = load();
    // 782b97f 에서 추가된 applied 분기. 형 제보 케이스(휴게소 추천)가 이쪽이다.
    (data['recommendation'] as Map)['highway_filter'] = {
      'requested': true,
      'applied': true,
      'fallback': null,
      'warning': null,
    };
    await pumpSheet(tester, data);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('고속도로 필터가 켜져 있어'), findsOneWidget);
  });

  // 실제로 휴게소가 추천된 응답 (수내역 → 천안시청 / LPG / 고속도로 ON,
  // highway_filter.applied=true, 1·2순위 모두 도로공사 휴게소).
  testWidgets('휴게소 추천 실응답 — 시트가 비지 않는다', (tester) async {
    final data = Map<String, dynamic>.from(jsonDecode(
        File('test/fixtures/refuel_analyze_lpg_highway_applied.json')
            .readAsStringSync()) as Map);
    await pumpSheet(tester, data);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('망향주유소'), findsWidgets);
  });

  testWidgets('station_aliases 박스가 없어도 시트는 그려진다', (tester) async {
    await Hive.box('station_aliases').close();
    addTearDown(() async => Hive.openBox('station_aliases'));

    final data = load();
    await pumpSheet(tester, data);

    expect(tester.takeException(), isNull);
    // 별칭을 못 읽어도 원본 이름으로 그대로 나온다.
    expect(find.textContaining('허스코'), findsWidgets);
  });

  testWidgets('build 가 던져도 흰 시트 대신 안내가 뜬다', (tester) async {
    final data = load();
    // 레이아웃 단계(LayoutBuilder) 안에서 터지는 예외 재현 —
    // `as Map<String, dynamic>` 캐스트가 실패하도록 타입만 망가뜨린다.
    data['computed'] = <dynamic, dynamic>{
      'reachable': <dynamic, dynamic>{'enabled': true},
    };
    await pumpSheet(tester, data);

    // 프레임워크에는 예외가 보고되지만(=원래는 백지가 되던 상황)
    tester.takeException();
    // 화면엔 안내 + 추천 주유소 이름이 남는다.
    expect(find.textContaining('추천 상세를 표시하지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
