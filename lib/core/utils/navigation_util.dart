import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_dialog.dart';
import '../constants/api_constants.dart';
import '../theme/app_colors.dart';
import 'nav_app_pref.dart';
import 'nav_scope_pref.dart';

// 길안내 오안내 주의 안내 "다시 보지 않기" 플래그 (일반/휴게소 별도, 전 내비 공통).
// 제보 반영: ① 좌표가 어긋난 주유소·충전소는 어느 내비 앱이든 엉뚱한 위치로 안내될
// 수 있음(티맵·네이버·카카오 공통 — 주소 직접 검색은 정상). ② 휴게소·고속도로
// 목적지는 지도 앱이 "도착지가 고속(화)도로에 위치 → 변경?" 팝업으로 목적지를
// 일반도로로 바꾸도록 유도하는데 [도착지 유지]가 정답.
const _kNavWarnOff = 'nav_warn_off';
const _kNavWarnRestOff = 'nav_warn_rest_off';

/// 길안내 경유지/목적지 한 지점.
class NavStop {
  final String name;
  final double lat;
  final double lng;
  const NavStop({required this.name, required this.lat, required this.lng});
}

/// AI 탭에서 사용자가 넣은 경유지 — 결과 화면·상세 시트가 파라미터로 들고 다니지 않아도
/// 내비 호출이 그대로 쓸 수 있게 세션에 보관한다. 추천 실행 시점에 갱신된다.
class AiRouteSession {
  AiRouteSession._();
  static List<NavStop> vias = const [];
  static void set(List<NavStop> v) => vias = List.unmodifiable(v);
  static void clear() => vias = const [];
}

/// 앱별 경유지 수용 한계 (공식 문서 기준)
///   티맵 rV1~rV5 = 5 / 카카오 viaList = 3 / 네이버 v1~v3 = 3
const int _kTmapViaMax = 5;
const int _kKakaoViaMax = 3;
const int _kNaverViaMax = 3;

/// 단순 목적지 길안내 (충전소/주유소 직접 안내)
///
/// [destination] 을 주면 시트 상단에 "주유소까지 / 목적지까지" 선택이 뜨고,
/// 목적지까지를 고르면 [lat]/[lng] 지점과 [waypoints] 를 경유지로 넘긴다.
Future<void> showNavigationSheet(
  BuildContext context, {
  required double lat,
  required double lng,
  required String name,
  NavStop? destination,
  List<NavStop> waypoints = const [],
  NavStop? origin,

  /// 경로 카드의 주유소·충전소 줄에 붙일 보조 문구 (예: '+1분 · 1,823원/L').
  /// 없으면 '경유' 만 표시한다.
  String? stationNote,

  /// 안내 범위 세그먼트에 쓸 지점 종류 — '주유소' | '충전소'.
  /// 안 넘기면 '여기까지만' 으로 표시한다(어느 쪽인지 모를 때).
  String? stopKind,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true, // 경로 카드·앱 선택이 붙어도 작은 화면에서 잘리지 않게
    backgroundColor: Colors.transparent,
    builder: (_) => _NavigationSheet(
      lat: lat,
      lng: lng,
      name: name,
      destination: destination,
      waypoints: waypoints,
      origin: origin,
      stationNote: stationNote,
      stopKind: stopKind,
    ),
  );
}

/// 경유지 포함 길안내 — 추천 주유소/충전소를 거쳐 최종 목적지까지.
///
/// 예전에는 "내비 앱이 경유지를 못 받는다"고 보고 주유소까지만 안내했는데,
/// 3사 모두 경유지를 지원한다(티맵 5 / 카카오 3 / 네이버 3). 사용자가 AI 탭에서
/// 넣은 경유지 [extraWaypoints] 도 순서 그대로 함께 넘긴다.
Future<void> showViaWaypointNavigationSheet(
  BuildContext context, {
  required double originLat,
  required double originLng,
  String originName = '',
  required double waypointLat,
  required double waypointLng,
  required String waypointName,
  required double destinationLat,
  required double destinationLng,
  required String destinationName,
  List<NavStop> extraWaypoints = const [],
  String? stationNote,
  String? stopKind,
}) async {
  await showNavigationSheet(
    context,
    lat: waypointLat,
    lng: waypointLng,
    name: waypointName,
    destination: NavStop(
      name: destinationName,
      lat: destinationLat,
      lng: destinationLng,
    ),
    // 명시 전달이 없으면 AI 탭에서 넣은 경유지를 그대로 쓴다
    waypoints: extraWaypoints.isNotEmpty ? extraWaypoints : AiRouteSession.vias,
    origin: NavStop(name: originName, lat: originLat, lng: originLng),
    stationNote: stationNote,
    stopKind: stopKind,
  );
}

// 고속도로 휴게소 식별 — '휴게소' 글자뿐 아니라 (도시방향)/(상)/(하) 표기까지.
// 주유소는 "(주)서원문경(하)주유소"·"안성(서울)주유소"처럼 휴게소 글자 없는 경우가 많아
// 이전엔 티맵 권장이 안 떴음. BrandLogo.isHighwayRestArea 와 동일 판정.
final RegExp _highwayCityLabelRe = RegExp(
    r'\((?:서울|부산|인천|대구|광주|대전|울산|세종|일산|하남|양평|춘천|강릉|속초|삼척|영덕|포항|서부산|창원|통영|함양|광양|순천|장수|전주|완주|익산|목포|영암|무안|논산|당진|서천|천안|공주|청주|제천|남이|평택|양양|경산|마산|영천|상주|판교|충주|안동|경주|보령|군위|처인|산청|진영|포천|원주|동해|여주|횡성|평창|대관령)(?:방향)?\)');
final RegExp _updownRe = RegExp(r'\((?:상|하)\)');
bool _isRestArea(String name) =>
    name.contains('휴게소') ||
    _highwayCityLabelRe.hasMatch(name) ||
    _updownRe.hasMatch(name);

Future<void> _launch(String url, {required String fallback}) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    await launchUrl(Uri.parse(fallback), mode: LaunchMode.externalApplication);
  }
}

Future<void> _launchKakaoNavi({
  required String name,
  required double lat,
  required double lng,
  List<NavStop> vias = const [],
}) async {
  try {
    if (await NaviApi.instance.isKakaoNaviInstalled()) {
      // navigate() 는 길안내가 곧바로 시작돼 사용자가 경로를 확인할 틈이 없다.
      // shareDestination() 은 내부적으로 routeInfo=true → 경로/목적지 화면을 띄우고
      // 사용자가 직접 안내 시작을 누른다. 티맵(tmap://route)과 동일한 동작.
      await NaviApi.instance.shareDestination(
        destination: Location(name: name, x: '$lng', y: '$lat'),
        option: NaviOption(coordType: CoordType.wgs84),
        // SDK 문서 기준 최대 3개 — 초과분은 호출부에서 이미 잘라서 넘긴다
        viaList: vias.isEmpty
            ? null
            : vias
                .map(
                    (v) => Location(name: v.name, x: '${v.lng}', y: '${v.lat}'))
                .toList(),
      );
    } else {
      await launchUrl(
        Uri.parse(NaviApi.webNaviInstall),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {
    await launchUrl(
      Uri.parse('https://kakaonavi.kakao.com'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// 경로 카드 한 줄 — 추천 지점(주유소/충전소)인지 사용자 경유지인지 구분해 들고 다닌다.
class _Stop {
  final NavStop stop;
  final bool isStation; // true = 추천 주유소·충전소 (끌 수 없음)
  const _Stop(this.stop, {required this.isStation});
}

class _NavigationSheet extends StatefulWidget {
  final double lat, lng;
  final String name;
  final NavStop? destination;
  final List<NavStop> waypoints;
  final NavStop? origin; // 경유지 순서 정렬 기준
  final String? stationNote;
  final String? stopKind;
  const _NavigationSheet({
    required this.lat,
    required this.lng,
    required this.name,
    this.destination,
    this.waypoints = const [],
    this.origin,
    this.stationNote,
    this.stopKind,
  });

  @override
  State<_NavigationSheet> createState() => _NavigationSheetState();
}

class _NavigationSheetState extends State<_NavigationSheet> {
  /// 열 때 기본은 '목적지까지 + 경유지 전부 켜짐'.
  /// 설정 화면에서 '주유소까지'를 명시적으로 고른 사용자만 그 값으로 시작한다.
  /// (시트 안에서 끈 건 저장하지 않으므로 다음에 열면 다시 전부 켜진 상태다)
  late bool _toDestination = NavScopePref.toDestination;
  late String _app = NavAppPref.get();

  /// 사용자가 끈 경유지 — _ordered 인덱스 기준. 주유소 줄은 절대 들어오지 않는다.
  final Set<int> _viaOff = <int>{};

  double get lat => widget.lat;
  double get lng => widget.lng;
  String get name => widget.name;

  bool get _hasDest => widget.destination != null;

  /// 경유 후보 전체 — 추천 지점 + 사용자 경유지를 **출발지에서 가까운 순**으로 정렬.
  /// 예전엔 추천 주유소를 무조건 맨 앞에 넣어서, 실제로는 경유지를 지나서 있는 주유소가
  /// '경유지 1' 로 들어가 경로가 엉켰다(형 제보).
  List<_Stop> get _ordered {
    final list = <_Stop>[
      _Stop(NavStop(name: name, lat: lat, lng: lng), isStation: true),
      ...widget.waypoints.map((w) => _Stop(w, isStation: false)),
    ];
    final o = widget.origin;
    if (o == null || list.length < 2) return list;
    return [...list]
      ..sort((a, b) => _distSq(o, a.stop).compareTo(_distSq(o, b.stop)));
  }

  /// 정렬용 상대 거리 — 순서만 필요해 제곱 비교로 충분(경도 보정 포함).
  static double _distSq(NavStop from, NavStop to) {
    final dLat = to.lat - from.lat;
    final dLng = (to.lng - from.lng) * 0.79; // 위도 37도 부근 경도 축소율
    return dLat * dLat + dLng * dLng;
  }

  /// 실제 목적지 (목적지까지 모드면 최종 목적지, 아니면 추천 지점)
  NavStop get _goal => _toDestination && _hasDest
      ? widget.destination!
      : NavStop(name: name, lat: lat, lng: lng);

  /// 켜져 있는 경유지 (주유소는 항상 포함).
  List<_Stop> get _enabled {
    final all = _ordered;
    return [
      for (var i = 0; i < all.length; i++)
        if (all[i].isStation || !_viaOff.contains(i)) all[i],
    ];
  }

  /// 앱에 실제로 넘길 경유지.
  ///
  /// ★ 한도(티맵5·카카오3·네이버3)를 넘으면 **주유소는 절대 빼지 않고** 사용자 경유지부터
  ///   앞에서 순서대로 채운다. 예전 take(max) 는 주유소가 정렬상 뒤에 있으면 잘려나가
  ///   "주유소를 들르려고 눌렀는데 안 들르는" 경로가 나갔다.
  List<NavStop> _viasFor(int max) {
    if (!(_toDestination && _hasDest)) return const [];
    final on = _enabled; // 순서 = 출발지 근접순
    if (on.length <= max) return on.map((e) => e.stop).toList();

    // 한도 초과 — 주유소 한 자리를 먼저 빼두고, 남는 칸만 사용자 경유지로 앞에서부터 채운다.
    // 순서는 그대로 유지된다.
    var budget = on.any((e) => e.isStation) ? max - 1 : max;
    final out = <NavStop>[];
    for (final s in on) {
      if (s.isStation) {
        out.add(s.stop); // 항상 통과 — 끌 수도, 잘릴 수도 없다
      } else if (budget > 0) {
        out.add(s.stop);
        budget--;
      }
    }
    return out;
  }

  int get _maxForApp => switch (_app) {
        NavAppPref.naver => _kNaverViaMax,
        NavAppPref.kakao => _kKakaoViaMax,
        _ => _kTmapViaMax,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface1 : Colors.white;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    // 작은 화면에서도 CTA 까지 닿게 — 넘치면 가운데 영역만 스크롤된다.
    final maxH = MediaQuery.of(context).size.height * 0.9;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      constraints: BoxConstraints(maxHeight: maxH),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0x33FFFFFF) : const Color(0xFFDDE3EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '길 안내 시작',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 세그먼트·힌트·경유지 카드 3덩어리를 경로 카드 하나로 합쳤다.
                    // 위→아래로 실제 이동 순서가 그려지니 "뭘 끄면 어떻게 되는지" 가
                    // 설명 없이 읽힌다(형 판단).
                    _routeCard(isDark),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '앱 선택',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: isDark
                              ? AppColors.darkBlueBright
                              : AppColors.gasBlueDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _appPicker(isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _startButton(context),
            ),
            const SizedBox(height: 10),
            Text('다음에도 이 앱으로 바로 열어드려요',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── 경로 카드 ──────────────────────────────────────────────────────────────
  // 현재 위치 → (경유 지점들) → 목적지 를 위에서 아래로. 각 줄의 스위치가 곧
  // "이 지점을 들를지" 라서 별도 설명이 필요 없다.
  //  · 주유소·충전소 줄엔 스위치가 없다 — 이 시트를 연 목적 자체라 끌 수 있으면 안 된다.
  //  · 목적지 스위치를 끄면 주유소가 종점이 되고(기존 '주유소까지만'), 그 아래 경유지는
  //    갈 일이 없으므로 흐려진다.
  //  · 앱 한도(카카오·네이버 3곳)에 밀려 못 넘기는 줄은 그 자리에서 이유를 말한다.
  //    '미전달' 같은 말 대신 "카카오내비에선 빠져요" — 뭘 해야 하는지가 바로 읽히게.
  Widget _routeCard(bool isDark) {
    final cardBg =
        isDark ? AppColors.darkGasActiveCard : AppColors.lightGasActiveCard;
    final line = isDark ? const Color(0x2EFFFFFF) : const Color(0xFFC3D9F5);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final warn = isDark ? AppColors.darkOrangeBright : const Color(0xFFE07000);

    final stops = _ordered;
    final sent = _viasFor(_maxForApp).toSet();
    final kind = widget.stopKind ?? '이곳';

    final rows = <Widget>[
      _stopRow(
        isDark: isDark,
        icon: Icons.circle,
        iconSize: 10,
        iconColor: isDark ? AppColors.darkTextMuted : const Color(0xFF9BA8B9),
        title: (widget.origin?.name.trim().isNotEmpty ?? false)
            ? widget.origin!.name
            : '현재 위치',
        titleMuted: true,
        line: line,
        showLine: true,
      ),
    ];

    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final isVia = !s.isStation;
      final on = !isVia || !_viaOff.contains(i);
      // 목적지 안내를 끄면 주유소가 종점 → 그 뒤 경유지는 의미가 없다.
      final disabled = isVia && !_toDestination;
      final dropped = isVia && on && !disabled && !sent.contains(s.stop);

      final String sub;
      if (s.isStation) {
        final note = widget.stationNote?.trim();
        sub = (note != null && note.isNotEmpty) ? '경유 · $note' : '경유';
      } else if (dropped) {
        sub = '${NavAppPref.label(_app)}에선 빠져요';
      } else if (disabled) {
        sub = '목적지까지 안내할 때만 들러요';
      } else {
        sub = on ? '경유' : '안 들러요';
      }

      rows.add(_stopRow(
        isDark: isDark,
        icon:
            s.isStation ? Icons.local_gas_station_rounded : Icons.place_rounded,
        iconSize: 18,
        iconColor: s.isStation
            ? AppColors.gasBlue
            : (dropped
                ? warn
                : (isDark
                    ? AppColors.darkTextSecondary
                    : const Color(0xFF64748B))),
        title: s.stop.name,
        subtitle: sub,
        subtitleColor: dropped ? warn : null,
        dimmed: (!on || disabled) && !dropped,
        line: line,
        showLine: true,
        trailing: s.isStation
            ? null
            : _switch(
                value: on,
                enabled: !disabled,
                onChanged: (v) =>
                    setState(() => v ? _viaOff.remove(i) : _viaOff.add(i)),
              ),
      ));
    }

    if (_hasDest) {
      rows.add(_stopRow(
        isDark: isDark,
        icon: Icons.flag_rounded,
        iconSize: 18,
        iconColor: isDark ? AppColors.darkTextPrimary : const Color(0xFF334155),
        title: widget.destination!.name,
        subtitle: _toDestination ? '최종 목적지까지 안내' : '$kind에서 안내가 끝나요',
        dimmed: !_toDestination,
        line: line,
        showLine: false,
        // ★ 이 스위치는 '이번 안내' 에만 적용된다 — NavScopePref 에 저장하지 않는다.
        //   예전엔 껐을 때 전역 설정까지 바꿔서, 한 번 끄면 다음부터 계속 꺼진 채로
        //   열렸다(형 제보: 디폴트는 목적지까지 + 경유지 전부 켜짐이어야 함).
        //   전역 기본값은 설정 화면의 '길안내 범위' 타일에서만 바꾼다.
        trailing: _switch(
          value: _toDestination,
          enabled: true,
          onChanged: (v) => setState(() => _toDestination = v),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          // 한도에 밀린 줄이 있을 때만 — 어떻게 하면 되는지 한 줄.
          if (_toDestination && _enabled.length > _maxForApp) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: warn),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${NavAppPref.label(_app)}는 주유소 포함 $_maxForApp곳까지만 받아요. '
                    '다른 앱을 고르거나, 안 들를 곳을 꺼주세요.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: warn),
                  ),
                ),
              ],
            ),
          ],
          if (!_hasDest) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 31),
              child: Text('이 지점으로 안내를 시작해요',
                  style: TextStyle(fontSize: 12, color: muted)),
            ),
          ],
        ],
      ),
    );
  }

  /// 경로 카드 한 줄 — 왼쪽 아이콘 + 세로 연결선, 오른쪽 스위치(있을 때).
  /// 연결선 높이는 줄마다 다르므로 IntrinsicHeight 로 실제 높이에 맞춘다
  /// (고정 높이로 두면 큰 글씨 설정에서 선이 끊기거나 넘친다).
  Widget _stopRow({
    required bool isDark,
    required IconData icon,
    required double iconSize,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? subtitleColor,
    bool titleMuted = false,
    bool dimmed = false,
    required Color line,
    required bool showLine,
    Widget? trailing,
  }) {
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  SizedBox(
                    height: 22,
                    child: Center(
                        child: Icon(icon, size: iconSize, color: iconColor)),
                  ),
                  if (showLine)
                    Expanded(child: Container(width: 1.5, color: line)),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: showLine ? 16 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        fontWeight:
                            titleMuted ? FontWeight.w600 : FontWeight.w700,
                        letterSpacing: -0.2,
                        color: titleMuted ? muted : textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: subtitleColor != null
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: subtitleColor ?? muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 1), child: trailing),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switch({
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 26,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.gasBlue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  // ── 내비 앱 선택 ───────────────────────────────────────────────────────────
  Widget _appPicker(bool isDark) {
    Widget tile(String key, String asset, String label) {
      final on = _app == key;
      final border =
          isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_app == key) return;
            setState(() => _app = key);
            NavAppPref.set(key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.gasBlue.withValues(alpha: isDark ? 0.16 : 0.06)
                  : (isDark ? AppColors.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? AppColors.gasBlue : border,
                width: on ? 1.6 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavAssetIcon(asset, size: 42),
                const SizedBox(height: 9),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.3,
                    color: on
                        ? (isDark
                            ? AppColors.darkBlueBright
                            : AppColors.gasBlueDark)
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(NavAppPref.tmap, 'assets/nav/tmap_logo.webp', '티맵'),
        const SizedBox(width: 10),
        tile(NavAppPref.naver, 'assets/nav/naver_logo.png', '네이버'),
        const SizedBox(width: 10),
        tile(NavAppPref.kakao, 'assets/nav/kakaomap_logo.png', '카카오내비'),
      ],
    );
  }

  Widget _startButton(BuildContext context) {
    return SizedBox(
      width: double.infinity, // 시트 폭을 꽉 채운다 — 안 주면 라벨 크기만큼만 그려짐
      height: 54,
      child: ElevatedButton.icon(
        onPressed: () => _startNav(context),
        icon: const Icon(Icons.navigation_rounded, size: 20),
        // ElevatedButton.icon 이 label 을 이미 Flexible 로 감싼다(_ElevatedButtonWithIcon).
        // 여기서 또 감싸면 Flexible 이 Flex 직속이 아니게 돼 런타임 assertion 으로 터진다.
        // 폭 제한은 그 Flexible 이 해주므로 maxLines+ellipsis 만 걸면 된다.
        label: Text(
          '${NavAppPref.labelWithRo(_app)} 안내 시작',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gasBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _startNav(BuildContext context) {
    switch (_app) {
      case NavAppPref.naver:
        return _tapNav(
          context,
          naver: true,
          () => _launch(_naverUrl(), fallback: 'https://map.naver.com'),
        );
      case NavAppPref.kakao:
        return _tapNav(
          context,
          () => _launchKakaoNavi(
            name: _goal.name,
            lat: _goal.lat,
            lng: _goal.lng,
            vias: _viasFor(_kKakaoViaMax),
          ),
        );
      default:
        return _tapNav(context, _launchTmap);
    }
  }

  /// 티맵 실행.
  ///
  /// 경유지는 URL 스킴으로 못 넘긴다 — 앱키 인증이 필요해서 공식 SDK(Tapi)를 쓴다.
  /// SDK 는 HashMap 을 받아 rGo*/rSt*/rV1~5 키로 티맵 앱을 띄운다(안드로이드·iOS 동일).
  /// SDK 호출이 실패하면(미설치·인증 실패) 검증된 URL 스킴(목적지만)으로 떨어진다.
  static const _tmapChannel = MethodChannel('com.dksw.charge/tmap');

  Future<void> _launchTmap() async {
    final vias = _viasFor(_kTmapViaMax);
    final o = widget.origin;
    if (vias.isNotEmpty) {
      final g = _goal;
      final info = <String, String>{
        'rGoName': g.name,
        'rGoX': '${g.lng}',
        'rGoY': '${g.lat}',
      };
      if (o != null) {
        info['rStName'] = o.name.trim().isEmpty ? '출발지' : o.name;
        info['rStX'] = '${o.lng}';
        info['rStY'] = '${o.lat}';
      }
      for (var i = 0; i < vias.length; i++) {
        info['rV${i + 1}Name'] = vias[i].name;
        info['rV${i + 1}X'] = '${vias[i].lng}';
        info['rV${i + 1}Y'] = '${vias[i].lat}';
      }
      try {
        final res = await _tmapChannel.invokeMapMethod<String, dynamic>(
          'invokeRoute',
          {'appKey': ApiConstants.tmapAppKey, 'routeInfo': info},
        );
        if (res?['ok'] == true) return;
        debugPrint('[TMAP] SDK 실패(${res?['reason']}) → URL 폴백(목적지만)');
      } catch (e) {
        debugPrint('[TMAP] SDK 호출 실패 → URL 폴백: $e');
      }
    }
    await _launch(
      Uri(scheme: 'tmap', host: 'route', queryParameters: {
        'goalname': _goal.name,
        'goaly': '${_goal.lat}',
        'goalx': '${_goal.lng}',
      }).toString(),
      fallback: 'https://www.tmap.co.kr',
    );
  }

  /// 네이버 URL — 목적지 dlat/dlng/dname + 경유지 v1~v3
  String _naverUrl() {
    final g = _goal;
    final b = StringBuffer('nmap://navigation?dlat=${g.lat}&dlng=${g.lng}'
        '&dname=${Uri.encodeComponent(g.name)}');
    final vias = _viasFor(_kNaverViaMax);
    for (var i = 0; i < vias.length; i++) {
      b.write('&v${i + 1}lat=${vias[i].lat}&v${i + 1}lng=${vias[i].lng}'
          '&v${i + 1}name=${Uri.encodeComponent(vias[i].name)}');
    }
    b.write('&appname=${AppConstants.packageName}');
    return b.toString();
  }

  /// 내비 앱 공통 — 첫 사용 시(또는 "다시 보지 않기" 전) 목적지 확인 안내 후 실행.
  /// 모든 주유소·충전소에서 표시. 고속(화)도로 [도착지 유지] 안내는 네이버 한정
  /// (네이버만 목적지를 일반도로로 바꾸도록 유도하는 팝업을 띄움).
  Future<void> _tapNav(BuildContext context, Future<void> Function() launchNav,
      {bool naver = false}) async {
    final box = Hive.box('settings');
    final highwayTip = naver && _isRestArea(name);
    final warnKey = highwayTip ? _kNavWarnRestOff : _kNavWarnOff;
    final skip = box.get(warnKey, defaultValue: false) == true;

    if (!skip) {
      final content = highwayTip
          ? '네이버 지도에서 "도착지가 고속(화)도로에 위치합니다. 주변 일반도로로 변경하시겠습니까?" 안내가 뜨면 반드시 [도착지 유지]를 선택하세요.\n\n'
              '[도착지 변경]을 누르면 고속도로 밖 엉뚱한 곳으로 안내될 수 있어요.'
          : '일부 주유소·충전소는 등록된 좌표가 실제 위치와 달라 길안내가 다른 곳으로 이어질 수 있어요.\n\n'
              '안내 시작 전에 목적지 이름과 위치를 꼭 확인하고, 다르면 주소로 검색해주세요.';
      // 공용 앱 다이얼로그(showAppDialog) — 앱 전반과 동일한 톤(아이콘·라운드·버튼).
      final choice = await showAppDialog<String>(
        context,
        icon: Icons.fork_right_rounded,
        title: '목적지를 확인해주세요',
        message: content,
        primaryLabel: '확인했어요',
        primaryValue: 'close',
        secondaryLabel: '다시 보지 않기',
        secondaryValue: 'never',
      );
      if (choice == null) return; // 바깥 탭 등으로 닫음 — 실행 안 함
      if (choice == 'never') await box.put(warnKey, true);
    }

    if (context.mounted) Navigator.pop(context); // 시트 닫기
    await launchNav();
  }
}

class _NavAssetIcon extends StatelessWidget {
  final String assetPath;
  final double size;
  const _NavAssetIcon(this.assetPath, {this.size = 48});

  @override
  Widget build(BuildContext context) {
    final r = size * 0.25;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(r),
          ),
          child: const Icon(Icons.map, color: Colors.grey),
        ),
      ),
    );
  }
}
