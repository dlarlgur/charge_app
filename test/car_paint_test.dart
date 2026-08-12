import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:charge_helper/ui/cheer/car_paint.dart';
import 'package:charge_helper/ui/cheer/cheer_tier_theme.dart';

/// 차 바디 컬러 치환 — 부위를 잘못 잡으면 미등이 파래지거나 휠 캘리퍼가 초록이 된다.
/// 실제 에셋 파일을 읽어 '바뀌어야 할 것/그대로여야 할 것'을 고정한다.
String _load(CheerTierTheme t) => File(t.carAsset).readAsStringSync();

int _count(String s, String needle) => needle.allMatches(s).length;

/// 차체 그라디언트 블록 안의 stop 수 (id 는 recolor 레시피와 동일 하드코딩).
int _bodyStops(String svg, String id) {
  final start = svg.indexOf('<linearGradient id="$id"');
  if (start < 0) return 0;
  final end = svg.indexOf('</linearGradient>', start);
  return _count(svg.substring(start, end), '<stop');
}

void main() {
  const tiers = CheerTierTheme.tiers;
  const paints = [
    CarPaint.red,
    CarPaint.blue,
    CarPaint.green,
    CarPaint.pearl,
    CarPaint.gold,
    CarPaint.black,
  ];

  test('기본 컬러는 원본 그대로', () {
    for (final t in tiers) {
      final src = _load(t);
      expect(recolorSvg(src, t.level, CarPaint.original), src);
    }
  });

  test('차체 그라디언트 stop 이 팔레트 색으로 바뀐다', () {
    for (final t in tiers) {
      final src = _load(t);
      for (final p in paints) {
        final out = recolorSvg(src, t.level, p);
        expect(out.length, greaterThan(0));
        expect(out.startsWith('<svg'), isTrue);
        // 그라디언트 블록 안에 팔레트 색이 들어갔는지
        final start = out.indexOf('<linearGradient');
        final end = out.indexOf('</linearGradient>', start);
        final block = out.substring(start, end);
        expect(block.contains(p.light), isTrue,
            reason: '${t.name} / ${p.name}: light stop 미적용');
        expect(block.contains(p.mid), isTrue,
            reason: '${t.name} / ${p.name}: mid stop 미적용');
      }
    }
  });

  test('태그 수·구조는 그대로 (치환이 마크업을 건드리지 않는다)', () {
    for (final t in tiers) {
      final src = _load(t);
      for (final p in paints) {
        final out = recolorSvg(src, t.level, p);
        expect(_count(out, '<path'), _count(src, '<path'));
        // 유광(프리미엄)은 차체 그라디언트를 글로시 4-stop 으로 통째로 다시 쓴다
        // (원본이 2-stop 이든 3-stop 이든 결과는 4). 그 외 구조는 전부 동일해야 한다.
        final bodyId = const {1: 'g', 2: 'body', 3: 'body3', 4: 'body4'}[t.level]!;
        final srcBodyStops = _bodyStops(src, bodyId);
        final expectStops = p.isPremium
            ? _count(src, '<stop') - srcBodyStops + 4
            : _count(src, '<stop');
        expect(_count(out, '<stop'), expectStops,
            reason: '${t.name} / ${p.name}');
        expect(_count(out, '<circle'), _count(src, '<circle'));
        expect(_count(out, '<linearGradient'), _count(src, '<linearGradient'));
      }
    }
  });

  test('스포츠카: 휠 캘리퍼 #DC2626 은 살고 차체 stop 만 바뀐다', () {
    final t = CheerTierTheme.byLevel(2);
    final src = _load(t);
    // 원본: 차체 stop 1 + 캘리퍼 stroke 2
    expect(_count(src, '#DC2626'), 3);

    final out = recolorSvg(src, 2, CarPaint.blue);
    expect(_count(out, 'stroke="#DC2626"'), 2, reason: '캘리퍼는 유지돼야 한다');
    expect(_count(out, 'stop-color="#DC2626"'), 0, reason: '차체 stop 은 바뀌어야 한다');
    expect(out.contains('stop-color="${CarPaint.blue.mid}"'), isTrue);
  });

  test('미등·헤드램프는 어떤 컬러에서도 원본 유지', () {
    // (색, 그 색을 쓰는 등급) — 각 SVG 주석으로 확인한 램프 부위
    final lamps = <int, List<String>>{
      1: ['fill="#EF4444"', 'fill="#DBEAFE"'],
      2: ['fill="#EF4444"', 'fill="#FEF3C7"', 'fill="#450A0A"'],
      3: ['fill="#F87171"', 'fill="#FEF3C7"', 'fill="#450A0A"'],
      4: ['fill="#F87171"', 'fill="#E5E7EB"', 'fill="#450A0A"'],
    };
    for (final t in tiers) {
      final src = _load(t);
      for (final p in paints) {
        final out = recolorSvg(src, t.level, p);
        for (final lamp in lamps[t.level]!) {
          expect(_count(out, lamp), _count(src, lamp),
              reason: '${t.name} / ${p.name}: $lamp 가 바뀌었다');
        }
      }
    }
  });

  test('슈퍼카: 차체 계열 하이라이트·음영도 같이 바뀐다', () {
    final src = _load(CheerTierTheme.byLevel(3));
    final out = recolorSvg(src, 3, CarPaint.green);
    // 후드 하이라이트 #FED7AA · 데크 패널 #EA580C · 카본 스커트 #7C2D12
    expect(out.contains('fill="#FED7AA"'), isFalse);
    expect(out.contains('fill="#EA580C"'), isFalse);
    expect(out.contains('fill="#7C2D12"'), isFalse);
    expect(out.contains('fill="${CarPaint.green.highlight}"'), isTrue);
    // 골드 휠은 그대로
    expect(_count(out, '#D4A017'), _count(src, '#D4A017'));
  });

  test('미드나잇 블랙 해금 — 하이퍼카 누적 120회부터', () {
    expect(CarPaint.blackUnlocked(119), isFalse);
    expect(CarPaint.blackUnlocked(120), isTrue);
  });

  test('유광 컬러 등급별 해금 — 펄 10회 · 골드 40회 · 블랙 120회', () {
    // 솔리드는 누구나
    expect(CarPaint.red.unlockedFor(0), isTrue);
    expect(CarPaint.original.unlockedFor(0), isTrue);
    // 펄 화이트 — 스포츠카(10회)
    expect(CarPaint.pearl.unlockedFor(9), isFalse);
    expect(CarPaint.pearl.unlockedFor(10), isTrue);
    // 샴페인 골드 — 슈퍼카(40회)
    expect(CarPaint.gold.unlockedFor(39), isFalse);
    expect(CarPaint.gold.unlockedFor(40), isTrue);
    // 미드나잇 블랙 — 하이퍼카(120회)
    expect(CarPaint.black.unlockedFor(119), isFalse);
    expect(CarPaint.black.unlockedFor(120), isTrue);
  });
}
