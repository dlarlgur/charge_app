import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';

/// 내 차 바디 컬러 — handoff 2 'CheerMain 5a-3 컬러 꾸미기'.
///
/// 시안 프로토는 hue-rotate 지만 실제 구현은 SVG 색상 교체(LEAD 지시). 차 SVG 원본은
/// 건드리지 않고, 런타임에 **차체 그라디언트 stop + 차체 계열 하이라이트/음영만**
/// 문자열 치환해 그린다. 미등·헤드램프·유리·휠·캘리퍼는 원본 그대로 둔다.
class CarPaint {
  final String id;
  final String name;

  /// 스와치 원(140° 그라디언트) — 시안 실측
  final List<Color> swatch;

  /// 차체 그라디언트 stop (밝음 → 중간 → 어두움)
  final String light, mid, dark;

  /// 차체 계열 하이라이트(펜더·후드 면) / 음영(로커·미러·슬랫)
  final String highlight, shade;

  /// 이 컬러가 열리는 등급(1이면 누구나). 등급이 오를수록 유광 컬러가 열린다.
  final int minLevel;

  const CarPaint({
    required this.id,
    required this.name,
    required this.swatch,
    required this.light,
    required this.mid,
    required this.dark,
    required this.highlight,
    required this.shade,
    this.minLevel = 1,
  });

  bool get isDefault => id == 'default';

  /// 승급 보상 유광 컬러 여부 — 스와치에 글로스 하이라이트를 얹는다.
  bool get isPremium => minLevel > 1;

  /// 누적 응원 횟수로 해금 판정. minLevel 등급의 threshold 에 도달하면 열린다.
  bool unlockedFor(int total) =>
      minLevel <= 1 || total >= CheerTierTheme.byLevel(minLevel).threshold;

  /// 기본(원본) 컬러 — 스와치는 등급 자기 차체색으로 그린다.
  static const original = CarPaint(
    id: 'default',
    name: '기본 컬러',
    swatch: [Color(0xFFFDBA74), Color(0xFFEA580C)], // 등급별로 덮어 쓴다
    light: '',
    mid: '',
    dark: '',
    highlight: '',
    shade: '',
  );

  static const red = CarPaint(
    id: 'red',
    name: '로쏘 레드',
    swatch: [Color(0xFFFCA5A5), Color(0xFFDC2626)],
    light: '#F87171',
    mid: '#DC2626',
    dark: '#991B1B',
    highlight: '#FCA5A5',
    shade: '#7F1D1D',
  );

  static const blue = CarPaint(
    id: 'blue',
    name: '아주로 블루',
    swatch: [Color(0xFF93C5FD), Color(0xFF2563EB)],
    light: '#60A5FA',
    mid: '#2563EB',
    dark: '#1E40AF',
    highlight: '#93C5FD',
    shade: '#1E3A8A',
  );

  static const green = CarPaint(
    id: 'green',
    name: '베르데 그린',
    swatch: [Color(0xFF6EE7B7), Color(0xFF059669)],
    light: '#34D399',
    mid: '#059669',
    dark: '#065F46',
    highlight: '#6EE7B7',
    shade: '#064E3B',
  );

  /// 스포츠카 승급 보상 — 유광 펄.
  /// 유광은 4-stop 글로시 그라디언트(recolorSvg)로 렌더된다: 순백 스페큘러 →
  /// 밝은 바디 → 반사 경계(급격한 명도 낙차) → 쿨 섀도. 파스텔 3톤이던 예전 값은
  /// "크레용 같다"는 형 피드백 — 경계 대비를 키워야 도장면 광이 산다.
  static const pearl = CarPaint(
    id: 'pearl',
    name: '펄 화이트',
    swatch: [Color(0xFFFFFFFF), Color(0xFFAFC0D4)],
    light: '#F8FBFF',
    mid: '#CDDAE9',
    dark: '#8CA1BB',
    highlight: '#FFFFFF',
    shade: '#66788F',
    minLevel: 2,
  );

  /// 슈퍼카 승급 보상 — 유광 샴페인 메탈. 스페큘러는 아이보리, 하부로 갈수록
  /// 브론즈에 가깝게 떨어뜨려 금속 깊이를 만든다.
  static const gold = CarPaint(
    id: 'gold',
    name: '샴페인 골드',
    swatch: [Color(0xFFFBEFC2), Color(0xFFBE9838)],
    light: '#F2DE9E',
    mid: '#C9A248',
    dark: '#8C6D26',
    highlight: '#FFF8DC',
    shade: '#5F4A18',
    minLevel: 3,
  );

  /// 하이퍼카 승급 보상 — 피아노 블랙. 스페큘러에 블루 시린(하늘 반사)을 넣고
  /// 미드부터 확 떨어뜨린다 — 검정 유광은 반사 낙차가 전부다.
  static const black = CarPaint(
    id: 'black',
    name: '미드나잇 블랙',
    swatch: [Color(0xFF46536A), Color(0xFF0B0F16)],
    light: '#3E4757',
    mid: '#12161D',
    dark: '#06080C',
    highlight: '#8B99B0',
    shade: '#04060A',
    minLevel: 4,
  );

  /// 스와치 순서 — 기본/솔리드 3색은 누구나, 그 뒤로 등급 승급 보상 유광 3색
  static const all = [original, red, blue, green, pearl, gold, black];

  static CarPaint byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => original);

  /// 미드나잇 블랙 해금 조건 — 하이퍼카 등급(누적 120회)
  static bool blackUnlocked(int total) => black.unlockedFor(total);
}

/// 등급별 치환 레시피 — SVG 안에서 '차체'로 판정한 것만 바꾼다.
/// (각 SVG 의 한글 주석으로 부위를 확인한 값이다. 미등 #EF4444/#F87171,
///  헤드램프 #FEF3C7, 유리, 휠 캘리퍼는 목록에 없어 원본이 유지된다.)
class _TierRecipe {
  /// 차체 linearGradient id
  final String bodyGradientId;

  /// 차체 계열 단색 — 원본 hex → 팔레트 슬롯('light'|'mid'|'dark'|'highlight'|'shade')
  final Map<String, String> solids;

  const _TierRecipe(this.bodyGradientId, this.solids);

  static const byLevel = {
    // 쿠페 — 실버 2 stop 그라디언트만. 휠 림 #9AA8BC 는 차체가 아니라 제외.
    1: _TierRecipe('g', {}),
    // 스포츠카 — 펜더 하이라이트/리어 볼륨 라인, 미러·슬랫·로커·리어 하부
    2: _TierRecipe('body', {
      '#FCA5A5': 'highlight',
      '#7F1D1D': 'shade',
    }),
    // 슈퍼카 — 후드 상면, 데크 핀 패널, 블레이드 라인·핀 슬랫, 카본 스커트
    3: _TierRecipe('body3', {
      '#FED7AA': 'highlight',
      '#EA580C': 'mid',
      '#9A3412': 'shade',
      '#7C2D12': 'shade',
    }),
    // 하이퍼카 — 차체 그라디언트만. 인테이크/디퓨저(#0A0C10)·노출 카본은 부위색이라 유지.
    4: _TierRecipe('body4', {}),
  };
}

/// 등급별 차 컬러 저장 — 비회원은 Hive, 로그인 회원은 서버(기기 바뀌어도 유지).
class CarPaintService {
  CarPaintService._();
  static final CarPaintService instance = CarPaintService._();

  static const _hiveKey = 'cheer_car_paints';

  /// 등급 → paintId. 기본색인 등급은 아예 키가 없다.
  final Map<int, String> _paints = {};
  bool _loadedLocal = false;

  /// 색이 바뀌면 히어로·개러지·승급 연출이 같이 따라오게 하는 알림.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Map<int, String> get paints => Map.unmodifiable(_paints);

  CarPaint of(int tierLevel) => CarPaint.byId(_paints[tierLevel]);

  void _loadLocal() {
    if (_loadedLocal) return;
    _loadedLocal = true;
    try {
      final raw = Hive.box('settings').get(_hiveKey) as String?;
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        final lv = int.tryParse(k);
        if (lv != null && v is String) _paints[lv] = v;
      });
    } catch (_) {}
  }

  void _saveLocal() {
    try {
      Hive.box('settings').put(
          _hiveKey, jsonEncode(_paints.map((k, v) => MapEntry('$k', v))));
    } catch (_) {}
  }

  /// 앱/화면 진입 시 1회 — 로컬 값을 먼저 읽어 첫 프레임부터 제 색으로 그린다.
  void init() {
    _loadLocal();
  }

  /// 서버 status 의 carPaints 반영 (로그인 회원만).
  ///
  /// 첫 로그인 1회는 '비회원으로 고른 색'을 서버로 올려주고, 그 뒤부터는 **서버가
  /// 원본**이다. 매번 로컬을 올려버리면 다른 기기에서 기본색으로 되돌린 등급이
  /// 이 기기 캐시 때문에 계속 되살아난다(타임스탬프가 없어 구분이 안 된다).
  Future<void> applyServer(Map<int, String>? server,
      {required bool signedIn}) async {
    _loadLocal();
    if (!signedIn) return;
    // null = 서버가 모름(조회 실패). {} 인 '저장 없음'과 달리 아무것도 하면 안 된다 —
    // 여기서 업로드하면 DB 가 잠깐 삐끗한 사이 로컬 캐시가 계정 색을 덮어쓴다.
    if (server == null) return;

    if (!_merged && server.isEmpty && _paints.isNotEmpty) {
      _merged = true;
      for (final e in _paints.entries) {
        await CheerService.instance.saveCarPaint(e.key, e.value);
      }
      return;
    }
    _merged = true;

    if (_sameAs(server)) return;
    _paints
      ..clear()
      ..addAll(server);
    _saveLocal();
    revision.value++;
  }

  bool _sameAs(Map<int, String> other) =>
      _paints.length == other.length &&
      _paints.entries.every((e) => other[e.key] == e.value);

  static const _mergedKey = 'cheer_car_paints_merged';

  bool get _merged {
    try {
      return Hive.box('settings').get(_mergedKey) == true;
    } catch (_) {
      return false;
    }
  }

  set _merged(bool v) {
    try {
      Hive.box('settings').put(_mergedKey, v);
    } catch (_) {}
  }

  /// 컬러 적용. 로컬은 항상 즉시 반영하고, 로그인 상태면 서버에도 저장한다.
  /// 서버 저장이 실패하면 false — 화면이 안내를 띄운다(로컬 값은 유지).
  Future<bool> set(int tierLevel, CarPaint paint) async {
    _loadLocal();
    if (paint.isDefault) {
      _paints.remove(tierLevel);
    } else {
      _paints[tierLevel] = paint.id;
    }
    _saveLocal();
    revision.value++;

    if (!await CheerService.instance.signedIn) return true;
    return CheerService.instance.saveCarPaint(tierLevel, paint.id);
  }

  // ─── SVG 리컬러 ───

  final Map<String, String> _srcCache = {}; // asset → 원본 문자열
  final Map<String, String> _outCache = {}; // 'level:paintId' → 치환본

  /// 치환본을 이미 갖고 있으면 즉시 반환 (없으면 null — 호출부가 원본을 그린다)
  String? cached(CheerTierTheme tier, CarPaint paint) =>
      _outCache['${tier.level}:${paint.id}'];

  Future<String> recolored(CheerTierTheme tier, CarPaint paint) async {
    final key = '${tier.level}:${paint.id}';
    final hit = _outCache[key];
    if (hit != null) return hit;

    var src = _srcCache[tier.carAsset];
    src ??= _srcCache[tier.carAsset] =
        await rootBundle.loadString(tier.carAsset);

    final out = recolorSvg(src, tier.level, paint);
    _outCache[key] = out;
    return out;
  }
}

/// 차 SVG 문자열에 바디 컬러를 입힌다 (원본 에셋은 그대로, 결과만 갈아끼운다).
/// 부위 판정이 틀리면 미등이 파래지는 식으로 티가 나므로 테스트로 고정해 둔다.
String recolorSvg(String svg, int tierLevel, CarPaint paint) {
  if (paint.isDefault) return svg;
  final recipe = _TierRecipe.byLevel[tierLevel];
  if (recipe == null) return svg;

  // 유광(프리미엄)은 4-stop 글로시 그라디언트로 통째로 다시 쓴다.
  // 원본의 3-stop(부드러운 셰이딩)에 색만 갈아끼우면 "크레용" 이 된다(형 피드백) —
  // 도장면 광은 스페큘러(0)와 반사 경계(0.42→0.56 급락)에서 나온다.
  var out = paint.isPremium
      ? _setGradientStops(svg, recipe.bodyGradientId, [
          ('0', paint.highlight),      // 순간 반사광 (하늘)
          ('0.42', paint.light),       // 밝은 바디면
          ('0.56', paint.mid),         // 반사 경계 — 급격한 명도 낙차가 '유광' 그 자체
          ('1', paint.dark),           // 하부 섀도
        ])
      : _replaceGradientStops(
          svg, recipe.bodyGradientId, [paint.light, paint.mid, paint.dark]);

  recipe.solids.forEach((hex, slot) {
    final to = switch (slot) {
      'light' => paint.light,
      'mid' => paint.mid,
      'dark' => paint.dark,
      'highlight' => paint.highlight,
      _ => paint.shade,
    };
    // fill/stroke 속성값만 — 그라디언트 stop 이나 다른 부위와 섞이지 않는다.
    out = out
        .replaceAll('fill="$hex"', 'fill="$to"')
        .replaceAll('stroke="$hex"', 'stroke="$to"');
  });
  return out;
}

/// 차체 그라디언트 블록의 stop 들을 지정한 (offset, color) 목록으로 통째로 교체.
/// 유광 4-stop 용 — stop 수가 원본과 달라져도 된다(글로시는 의도된 +1).
String _setGradientStops(String svg, String id, List<(String, String)> stops) {
  final start = svg.indexOf('<linearGradient id="$id"');
  if (start < 0) return svg;
  final headEnd = svg.indexOf('>', start);
  final end = svg.indexOf('</linearGradient>', start);
  if (headEnd < 0 || end < 0) return svg;
  final body = stops
      .map((s) => '<stop offset="${s.$1}" stop-color="${s.$2}"/>')
      .join();
  return svg.replaceRange(headEnd + 1, end, '\n$body\n');
}

/// 차체 그라디언트 블록 안의 stop-color 만 순서대로 교체.
/// (#DC2626 처럼 휠 캘리퍼에도 쓰인 색이 있어 파일 전체 치환은 못 한다)
String _replaceGradientStops(String svg, String id, List<String> stops) {
  final start = svg.indexOf('<linearGradient id="$id"');
  if (start < 0) return svg;
  final end = svg.indexOf('</linearGradient>', start);
  if (end < 0) return svg;

  var i = 0;
  final block = svg.substring(start, end).replaceAllMapped(
    RegExp(r'stop-color="#[0-9A-Fa-f]{6}"'),
    (m) {
      final hex = i < stops.length ? stops[i] : stops.last;
      i++;
      return 'stop-color="$hex"';
    },
  );
  return svg.replaceRange(start, end, block);
}

/// 컬러가 반영된 차 그림. 기본색이면 원본 에셋을 그대로 쓰고(가장 빠른 길),
/// 컬러가 걸려 있으면 치환본을 그린다. 치환본이 준비되기 전 한 프레임은
/// 원본을 보여줘 빈 자리가 생기지 않게 한다.
class CarImage extends StatefulWidget {
  final CheerTierTheme tier;

  /// null 이면 저장된 컬러를 따라간다. 미리보기처럼 특정 색을 강제할 때만 넘긴다.
  final CarPaint? paint;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CarImage({
    super.key,
    required this.tier,
    this.paint,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<CarImage> createState() => _CarImageState();
}

class _CarImageState extends State<CarImage> {
  String? _svg;
  String? _forKey;

  @override
  void initState() {
    super.initState();
    CarPaintService.instance.init();
  }

  CarPaint _paintOf() =>
      widget.paint ?? CarPaintService.instance.of(widget.tier.level);

  void _ensure(CarPaint paint) {
    final key = '${widget.tier.level}:${paint.id}';
    if (_forKey == key) return;
    _forKey = key;
    if (paint.isDefault) {
      _svg = null;
      return;
    }
    final hit = CarPaintService.instance.cached(widget.tier, paint);
    if (hit != null) {
      _svg = hit;
      return;
    }
    _svg = null;
    CarPaintService.instance.recolored(widget.tier, paint).then((s) {
      if (mounted && _forKey == key) setState(() => _svg = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CarPaintService.instance.revision,
      builder: (_, __, ___) {
        final paint = _paintOf();
        _ensure(paint);
        final svg = _svg;
        if (paint.isDefault || svg == null) {
          return widget.tier
              .car(width: widget.width, height: widget.height, fit: widget.fit);
        }
        return SvgPicture.string(svg,
            width: widget.width, height: widget.height, fit: widget.fit);
      },
    );
  }
}
