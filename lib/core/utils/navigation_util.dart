import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_dialog.dart';
import '../constants/api_constants.dart';
import '../theme/app_colors.dart';
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
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true, // 세그먼트·안내가 붙어도 작은 화면에서 잘리지 않게
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NavigationSheet(
      lat: lat,
      lng: lng,
      name: name,
      destination: destination,
      waypoints: waypoints,
      origin: origin,
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
      await NaviApi.instance.navigate(
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

class _NavigationSheet extends StatefulWidget {
  final double lat, lng;
  final String name;
  final NavStop? destination;
  final List<NavStop> waypoints;
  final NavStop? origin; // 경유지 순서 정렬 기준
  const _NavigationSheet({
    required this.lat,
    required this.lng,
    required this.name,
    this.destination,
    this.waypoints = const [],
    this.origin,
  });

  @override
  State<_NavigationSheet> createState() => _NavigationSheetState();
}

class _NavigationSheetState extends State<_NavigationSheet> {
  late bool _toDestination = NavScopePref.toDestination;

  double get lat => widget.lat;
  double get lng => widget.lng;
  String get name => widget.name;

  /// 목적지까지 안내할 때 넘길 경유지 — [추천 지점, 사용자 경유지…] 순서.
  /// 경유지 목록 — 추천 지점과 사용자 경유지를 **출발지에서 가까운 순**으로 정렬한다.
  /// 예전엔 추천 주유소를 무조건 맨 앞에 넣어서, 실제로는 경유지를 지나서 있는 주유소가
  /// '경유지 1' 로 들어가 경로가 엉켰다(형 제보).
  List<NavStop> get _stops {
    final list = <NavStop>[
      NavStop(name: name, lat: lat, lng: lng),
      ...widget.waypoints,
    ];
    final o = widget.origin;
    if (o == null || list.length < 2) return list;
    final sorted = [...list]
      ..sort((a, b) => _distSq(o, a).compareTo(_distSq(o, b)));
    return sorted;
  }

  /// 정렬용 상대 거리 — 순서만 필요해 제곱 비교로 충분(경도 보정 포함).
  static double _distSq(NavStop from, NavStop to) {
    final dLat = to.lat - from.lat;
    final dLng = (to.lng - from.lng) * 0.79; // 위도 37도 부근 경도 축소율
    return dLat * dLat + dLng * dLng;
  }

  /// 실제 목적지 (목적지까지 모드면 최종 목적지, 아니면 추천 지점)
  NavStop get _goal => _toDestination && widget.destination != null
      ? widget.destination!
      : NavStop(name: name, lat: lat, lng: lng);

  List<NavStop> _viasFor(int max) =>
      (_toDestination && widget.destination != null)
          ? _stops.take(max).toList()
          : const [];

  /// 앱별로 몇 곳이 잘리는지 — 시트에 그대로 알려준다(조용히 버리지 않게)
  String _viaNote(int max) {
    if (!(_toDestination && widget.destination != null)) return '';
    final n = _stops.length;
    if (n == 0) return '';
    return n <= max ? '경유 $n곳 전달' : '경유 $n곳 중 $max곳만 전달';
  }

  @override
  Widget build(BuildContext context) {
    final restArea = _isRestArea(name);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('길찾기 앱 선택',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (widget.destination != null) ...[
              _scopeChooser(isDark),
              const SizedBox(height: 4),
            ],
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/tmap_logo.webp'),
              label: '티맵',
              subtitle: _viaNote(_kTmapViaMax).isNotEmpty
                  ? _viaNote(_kTmapViaMax)
                  : (restArea ? '고속도로 휴게소는 티맵 안내를 권장해요' : 'SK텔레콤'),
              subtitleColor: restArea && _viaNote(_kTmapViaMax).isEmpty
                  ? const Color(0xFFE07000)
                  : Colors.grey,
              popBeforeTap: false,
              onTap: () => _tapNav(
                context,
                _launchTmap,
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/naver_logo.png'),
              label: '네이버 지도',
              subtitle: _viaNote(_kNaverViaMax).isNotEmpty
                  ? _viaNote(_kNaverViaMax)
                  : '네이버',
              popBeforeTap: false,
              onTap: () => _tapNav(
                context,
                naver: true,
                () => _launch(_naverUrl(), fallback: 'https://map.naver.com'),
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/kakaomap_logo.png'),
              label: '카카오내비',
              subtitle: _viaNote(_kKakaoViaMax).isNotEmpty
                  ? _viaNote(_kKakaoViaMax)
                  : '카카오',
              popBeforeTap: false,
              onTap: () => _tapNav(
                context,
                () => _launchKakaoNavi(
                  name: _goal.name,
                  lat: _goal.lat,
                  lng: _goal.lng,
                  vias: _viasFor(_kKakaoViaMax),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  /// 안내 범위 선택 — 매번 묻지 않고, 시트에서 바로 바꿀 수 있게.
  /// 안내 범위 선택 — "무엇을 고르는 건지" 가 바로 읽히게 질문 + 결과로 보여준다.
  /// (세그먼트만 있으면 뭘 선택하는지 몰라 헷갈린다는 피드백 반영)
  Widget _scopeChooser(bool isDark) {
    final border =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final viaCount = _stops.length;
    final destName = widget.destination?.name ?? '목적지';

    Widget option({
      required String value,
      required String title,
      required Widget detail,
      required IconData icon,
    }) {
      final on =
          (_toDestination ? NavScopePref.destination : NavScopePref.station) ==
              value;
      return GestureDetector(
        onTap: () {
          final next = value == NavScopePref.destination;
          if (next == _toDestination) return;
          setState(() => _toDestination = next);
          NavScopePref.set(value);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: on
                ? AppColors.gasBlue.withValues(alpha: isDark ? 0.16 : 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? AppColors.gasBlue.withValues(alpha: 0.55) : border,
              width: on ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                on
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: on ? AppColors.gasBlue : muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: -0.2,
                        color: on ? AppColors.gasBlue : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style:
                          TextStyle(fontSize: 11.5, height: 1.35, color: muted),
                      child: detail,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Icon(icon, size: 15, color: muted),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              '어디까지 안내할까요?',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: muted),
            ),
          ),
          option(
            value: NavScopePref.destination,
            title: '목적지까지',
            icon: Icons.flag_rounded,
            detail: Text(
              viaCount > 1
                  ? '$name 외 ${viaCount - 1}곳 들렀다가 → $destName'
                  : '$name 들렀다가 → $destName',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 7),
          option(
            value: NavScopePref.station,
            title: '$name 까지만',
            icon: Icons.local_gas_station_rounded,
            detail: const Text('도착하면 안내가 끝나요'),
          ),
        ],
      ),
    );
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

  Widget _navItem(
    BuildContext context, {
    required Widget icon,
    required String label,
    required String subtitle,
    Color subtitleColor = Colors.grey,
    required VoidCallback onTap,
    bool popBeforeTap = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: icon,
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle:
          Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () {
        if (popBeforeTap) Navigator.pop(context);
        onTap();
      },
    );
  }
}

class _NavAssetIcon extends StatelessWidget {
  final String assetPath;
  const _NavAssetIcon(this.assetPath);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        assetPath,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.map, color: Colors.grey),
        ),
      ),
    );
  }
}
