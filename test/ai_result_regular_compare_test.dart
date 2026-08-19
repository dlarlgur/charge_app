import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:charge_helper/core/constants/api_constants.dart';
import 'package:charge_helper/ui/ai/ai_result_screen.dart';

/// 결과 시트 백지 — 형 제보 2026-08-19.
/// 결정적 단서: **1.3.1(단골 기능 이전)에서는 같은 경로가 멀쩡하다.**
/// 즉 단골주유소를 등록한 뒤 서버가 내려주는 `regular_compare` 분기가 원인 후보다.
/// 기존 픽스처 2종은 모두 regular_compare=null 이라 이 분기가 검증된 적이 없다.
///
/// regular_compare 실제 형태 (charge_server refuelAnalyzeService.js:3695~3711):
///   {matched, station_id, approx_diff_won, is_primary, second_is_regular, cheaper_won?}
///   또는 {matched:false}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('charge_hive_regular');
    Hive.init(dir.path);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox('station_aliases');
    // 형 기기와 같은 상태 — 단골 1곳 등록됨.
    await box.put('regular_gas_station', [
      {'id': 'A0019559', 'name': '분당로주유소', 'brand': 'SKE'},
    ]);
  });

  final raw =
      File('test/fixtures/refuel_analyze_lpg_highway.json').readAsStringSync();
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

  /// 시트가 실제로 그려졌는지 — 추천 주유소 이름이 화면에 있어야 한다.
  /// 백지면 이 기대가 깨지고, 폴백이 뜨면 안내 문구가 잡힌다.
  void expectNotBlank(WidgetTester tester) {
    final fellBack = find.textContaining('추천 상세를 표시하지 못했어요');
    expect(fellBack, findsNothing,
        reason: '폴백이 떴다 = build 가 던졌다는 뜻 (원래는 백지)');
    expect(find.textContaining('허스코'), findsWidgets,
        reason: '추천 주유소 이름이 없으면 시트가 빈 것');
  }

  testWidgets('단골이 1순위 (is_primary=true)', (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'A0019559',
      'approx_diff_won': 0,
      'is_primary': true,
      'second_is_regular': false,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('1·2순위 모두 단골 (second_is_regular=true)', (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'A0019559',
      'approx_diff_won': 0,
      'is_primary': true,
      'second_is_regular': true,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('추천이 단골보다 이득 (approx_diff_won > 0)', (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'A0019559',
      'approx_diff_won': 1063,
      'is_primary': false,
      'second_is_regular': false,
      'cheaper_won': null,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
    expect(find.textContaining('분당로주유소'), findsWidgets);
  });

  testWidgets('단골이 더 저렴 (cheaper_won)', (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'A0019559',
      'approx_diff_won': 0,
      'is_primary': false,
      'second_is_regular': false,
      'cheaper_won': 940,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('서버가 단골을 못 찾음 (matched:false)', (tester) async {
    final data = load();
    data['regular_compare'] = {'matched': false};
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('다른 기기에서 등록해 로컬에 이름이 없는 단골 (station_id 미보유)',
      (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'ZZZ_UNKNOWN_ID',
      'approx_diff_won': 500,
      'is_primary': false,
      'second_is_regular': false,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('숫자가 문자열로 온 경우 (JSON 타입 흔들림)', (tester) async {
    final data = load();
    data['regular_compare'] = {
      'matched': true,
      'station_id': 'A0019559',
      'approx_diff_won': '1063',
      'is_primary': false,
      'second_is_regular': false,
    };
    await pumpSheet(tester, data);
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });
}
