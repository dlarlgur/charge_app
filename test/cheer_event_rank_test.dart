import 'package:charge_helper/data/services/cheer_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 진행 중인 달 순위 노출 규칙 (형 지시 2026-08-12):
///  - 내 등수를 숫자로 알려주지 않는다 → '2위가 쫓아와요' 식 추격 문구
///  - 남의 응원 횟수는 공개하지 않는다 → 서버 응답에도, 모델에도 없어야 한다
void main() {
  CheerEvent event({
    required int myCount,
    int? toTop,
    int? fromNext,
    List<Map<String, dynamic>> top = const [],
  }) =>
      CheerEvent.fromJson({
        'title': 't',
        'desc': 'd',
        'reward': 'r',
        'month': '2026-08',
        'myCount': myCount,
        'myRank': 1,
        'top': top,
        'chase': {'toTop': toTop, 'fromNext': fromNext},
      });

  group('추격 문구 — 등수 숫자를 쓰지 않는다', () {
    test('아직 응원 전', () {
      expect(cheerChaseCopy(event(myCount: 0)), '한 번만 응원해도 순위에 들어가요');
    });

    test('선두 · 바짝 쫓김', () {
      final c = cheerChaseCopy(event(myCount: 20, toTop: 0, fromNext: 3));
      expect(c, '바로 뒤가 3회 차이로 쫓아오고 있어요');
    });

    test('선두 · 동점', () {
      expect(cheerChaseCopy(event(myCount: 20, toTop: 0, fromNext: 0)),
          '바로 뒤와 동점이에요 — 한 번이면 앞서요');
    });

    test('선두 · 여유', () {
      expect(cheerChaseCopy(event(myCount: 30, toTop: 0, fromNext: 11)),
          '11회 차이로 앞서고 있어요');
    });

    test('선두 · 아래가 없음(혼자)', () {
      expect(cheerChaseCopy(event(myCount: 5, toTop: 0)), '지금 선두를 달리고 있어요');
    });

    test('추격 · 사정권', () {
      expect(cheerChaseCopy(event(myCount: 17, toTop: 3, fromNext: 8)),
          '1위까지 3회 — 오늘 따라잡을 수 있어요');
    });

    test('추격 · 멀다', () {
      expect(cheerChaseCopy(event(myCount: 4, toTop: 16)), '1위까지 16회 남았어요');
    });

    test('격차를 모르면 내 횟수만 말한다', () {
      expect(cheerChaseCopy(event(myCount: 7)), '이번 달 7회 응원했어요');
    });

    test('어떤 경우에도 "N위" 라는 등수 표기가 안 들어간다', () {
      final cases = [
        event(myCount: 0),
        event(myCount: 20, toTop: 0, fromNext: 3),
        event(myCount: 20, toTop: 0, fromNext: 0),
        event(myCount: 30, toTop: 0, fromNext: 11),
        event(myCount: 5, toTop: 0),
        event(myCount: 17, toTop: 3, fromNext: 8),
        event(myCount: 7),
      ];
      // '1위까지' 는 목표 지점을 가리키는 표현이라 허용 — 내 등수를 밝히는 게 아니다.
      final myRank = RegExp(r'(?<!1위까지 )\d+위');
      for (final e in cases) {
        final c = cheerChaseCopy(e);
        expect(myRank.hasMatch(c.replaceAll('1위까지', '')), isFalse,
            reason: '등수를 노출한다: $c');
      }
    });
  });

  group('남의 응원 횟수는 모델에 들어오지 않는다', () {
    test('서버가 실수로 count 를 보내도 CheerEventRank 는 무시한다', () {
      final r = CheerEventRank.fromJson(
          {'rank': 2, 'name': '임**식', 'count': 17, 'me': false});
      expect(r.rank, 2);
      expect(r.name, '임**식');
      expect(r.me, isFalse);
      // count 필드 자체가 없다 — 화면이 실수로 그릴 방법이 없다.
      expect(r.toString().contains('17'), isFalse);
    });

    test('top 목록 파싱은 순위·이름·본인여부만 남긴다', () {
      final ev = event(myCount: 20, toTop: 0, fromNext: 3, top: [
        {'rank': 1, 'name': '임건식', 'me': true},
        {'rank': 2, 'name': '충**렙', 'me': false},
      ]);
      expect(ev.top.length, 2);
      expect(ev.top.first.me, isTrue);
      expect(ev.top.last.name, '충**렙');
    });
  });
}
