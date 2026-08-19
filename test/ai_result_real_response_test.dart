import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:charge_helper/core/constants/api_constants.dart';
import 'package:charge_helper/ui/ai/ai_result_screen.dart';

/// 결과 시트 백지 재현 — 형 제보 경로 그대로.
///
/// 픽스처는 **운영 서버(charge.dksw4.com) 실응답**이다. 2026-08-19 채취:
///   수내역 수인분당선(37.3784687674046, 127.114288846291)
///     → 서울특별시중구청(37.5638077703663, 126.99755518229246)
///   LPG(K015) / 55L / 9.5km/L / 잔량 25% / FULL / 고속도로 필터 ON / 티맵 경로
///
///   · ..._sunae_junggu.json          — 단골 미등록
///   · ..._sunae_junggu_regular.json  — regular_station_id=A0011826 (추천 1순위 자체가 단골)
///
/// 기존 픽스처와 달리 이 응답은 best_detour=null · alternatives=[] ·
/// ranked_comparison=null 이다. 형 제보("1.3.1 은 멀쩡, 단골 넣고부터")의
/// 진위를 이 두 파일 비교로 가른다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('charge_hive_real');
    Hive.init(dir.path);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox('station_aliases');
    await box.put('regular_gas_station', [
      {'id': 'A0011826', 'name': '만남의광장주유소', 'brand': 'HDO'},
    ]);
  });

  Map<String, dynamic> load(String name) => Map<String, dynamic>.from(
      jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map);

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
                  destinationName: '서울특별시중구청',
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

  /// 백지 판정 — 추천 주유소 이름이 화면에 없으면 빈 시트다.
  void expectNotBlank(WidgetTester tester) {
    expect(find.textContaining('추천 상세를 표시하지 못했어요'), findsNothing,
        reason: '폴백이 떴다 = build 가 던졌다(수정 전이면 백지)');
    expect(find.textContaining('만남의광장'), findsWidgets,
        reason: '추천 주유소 이름이 없으면 시트가 빈 것');
  }

  testWidgets('실응답(단골 미등록) — 시트가 그려진다', (tester) async {
    await pumpSheet(tester, load('refuel_analyze_real_sunae_junggu.json'));
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });

  testWidgets('실응답(단골 등록, 1순위가 단골) — 시트가 그려진다', (tester) async {
    await pumpSheet(
        tester, load('refuel_analyze_real_sunae_junggu_regular.json'));
    expect(tester.takeException(), isNull);
    expectNotBlank(tester);
  });
}
