import 'dart:io';

import 'package:charge_helper/ui/widgets/settings_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 설정 행 레이아웃 회귀 테스트 — **앱 코드(SettingsValue)를 직접 pump** 한다.
///
/// ListTile 은 leading·trailing 을 먼저 배치하고 남은 폭을 title 에 준다.
/// 값(trailing)이 길면 타이틀이 0 폭까지 밀려 '광/고/문/의' 처럼 한 글자씩 세로로
/// 쪼개졌다(형 제보 2026-08-12).
void main() {
  const narrow = 320.0;

  /// 실제 설정 행과 같은 구성 — leading 아이콘 칩 + 타이틀 + [값] + chevron.
  /// [value] 를 SettingsValue 로 감쌀지(현재 코드) 그냥 Text 로 둘지(수정 전)만 다르다.
  Widget row(String title, String value, {required bool useAppRule}) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(narrow, 640)),
        child: Scaffold(
          body: SizedBox(
            width: narrow,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: const SizedBox(width: 38, height: 38),
              title: Text(title,
                  key: const Key('title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                useAppRule ? SettingsValue(value) : Text(value),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ]),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  void useNarrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(narrow, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('SettingsValue 를 쓰면 긴 값에도 타이틀 폭이 남는다', (tester) async {
    useNarrowScreen(tester);
    await tester.pumpWidget(
        row('광고 문의', '앱 지면에 광고를 싣고 싶다면', useAppRule: true));

    final size = tester.getSize(find.byKey(const Key('title')));
    // 굶으면 폭이 20px 안팎까지 줄고 높이가 여러 줄로 늘어난다.
    expect(size.width, greaterThan(60),
        reason: '타이틀이 굶었다 — SettingsValue 의 폭 상한이 동작하지 않는다');
    expect(size.height, lessThan(30), reason: '타이틀이 여러 줄로 쪼개졌다');
  });

  testWidgets('SettingsValue 없이 그냥 Text 면 타이틀이 굶는다 (회귀 재현)',
      (tester) async {
    useNarrowScreen(tester);
    await tester.pumpWidget(
        row('광고 문의', '앱 지면에 광고를 싣고 싶다면', useAppRule: false));

    final size = tester.getSize(find.byKey(const Key('title')));
    expect(size.width, lessThan(60),
        reason: '재현이 안 되면 위 테스트가 아무것도 보장하지 못한다');
  });

  testWidgets('SettingsValue 는 화면 폭의 maxWidthRatio 를 넘지 않는다',
      (tester) async {
    useNarrowScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(narrow, 640)),
        child: const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SettingsValue('아주아주 길고 긴 설정 값 텍스트 예시입니다 정말로'),
          ),
        ),
      ),
    ));

    final w = tester.getSize(find.byType(SettingsValue)).width;
    expect(w, lessThanOrEqualTo(narrow * SettingsValue.maxWidthRatio + 0.5));
  });

  testWidgets('짧은 값은 잘리지 않고 그대로 보인다', (tester) async {
    useNarrowScreen(tester);
    await tester.pumpWidget(row('차량 타입', '둘 다 사용', useAppRule: true));

    expect(find.text('둘 다 사용'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('title'))).height, lessThan(30));
  });

  testWidgets('빈 값이면 아무것도 그리지 않는다', (tester) async {
    useNarrowScreen(tester);
    await tester.pumpWidget(row('정책 및 약관', '', useAppRule: true));

    expect(find.byType(SettingsValue), findsOneWidget);
    expect(tester.getSize(find.byType(SettingsValue)).width, 0);
  });

  /// 위 테스트들은 SettingsValue 자체를 지킨다. 하지만 설정 행 **빌더**가 이 위젯을
  /// 부르지 않게 바뀌면(원래 회귀의 형태) 위젯 테스트는 여전히 초록이다.
  /// 빌더가 Riverpod·Hive 에 묶인 private 함수라 pump 로는 못 잡으므로,
  /// 해당 함수 본문에 규칙 호출이 있는지 소스에서 확인한다.
  ///
  /// 파일 전체를 훑으면 안 된다 — 같은 파일의 다른 타일이 SettingsValue 를 쓰고
  /// 있으면 _tile 에서 호출을 지워도 통과해 버린다(실제로 그랬다).
  test('설정 행 빌더 본문이 SettingsValue 를 경유한다', () {
    /// [path] 에서 [signature] 로 시작하는 함수의 본문(다음 최상위 멤버 전까지)
    String body(String path, String signature, String stopAt) {
      final src = File(path).readAsStringSync();
      final start = src.indexOf(signature);
      expect(start, isNot(-1), reason: '$path 에서 $signature 를 못 찾았다');
      final end = src.indexOf(stopAt, start + signature.length);
      return src.substring(start, end == -1 ? src.length : end);
    }

    final tile = body(
        'lib/ui/home/home_screen.dart',
        'Widget _tile(BuildContext context, bool isDark, IconData icon',
        '\n  void _showPicker(');
    expect(tile.contains('SettingsValue('), isTrue,
        reason: 'home_screen._tile 이 값 폭 상한을 건너뛴다');

    // stopAt 은 그 함수 **바로 다음 멤버**여야 한다. '\n  Widget ' 로 두면 뒤따르는
    // void 멤버들을 못 걸러 슬라이스가 133줄 더 먹고, 그 안 아무 데나 SettingsValue 가
    // 생기면 정작 _settingTile 의 호출이 사라져도 통과한다.
    final settingTile = body('lib/ui/settings/settings_screen.dart',
        'Widget _settingTile(', '\n  void _showPickerSheet(');
    expect(settingTile.contains('SettingsValue('), isTrue,
        reason: 'settings_screen._settingTile 이 값 폭 상한을 건너뛴다');
  });
}
