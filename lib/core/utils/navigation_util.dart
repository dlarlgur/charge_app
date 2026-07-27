import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';

// 네이버 지도 오안내 주의 안내 "다시 보지 않기" 플래그 (일반/휴게소 별도).
// 제보 반영: ① 좌표가 어긋난 곳은 엉뚱한 위치로 안내될 수 있음. ② 휴게소·고속도로
// 목적지는 네이버가 "도착지가 고속(화)도로에 위치합니다 → 변경?" 팝업을 띄우는데
// [도착지 변경]을 누르면 고속도로 밖 엉뚱한 일반도로로 안내됨 — [도착지 유지]가 정답.
const _kNaverNavWarnOff = 'naver_nav_warn_off';
const _kNaverNavWarnRestOff = 'naver_nav_warn_rest_off';

/// 단순 목적지 길안내 (충전소/주유소 직접 안내)
Future<void> showNavigationSheet(
  BuildContext context, {
  required double lat,
  required double lng,
  required String name,
}) async {
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NavigationSheet(lat: lat, lng: lng, name: name),
  );
}

/// 경유지 포함 길안내 — 충전소/주유소를 목적지로 안내
/// (네비 앱이 아니므로 충전소까지만 안내하는 것이 자연스러움)
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
}) async {
  // 충전소(경유지)를 목적지로 단순 안내
  await showNavigationSheet(
    context,
    lat: waypointLat,
    lng: waypointLng,
    name: waypointName,
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
}) async {
  try {
    if (await NaviApi.instance.isKakaoNaviInstalled()) {
      await NaviApi.instance.navigate(
        destination: Location(name: name, x: '$lng', y: '$lat'),
        option: NaviOption(coordType: CoordType.wgs84),
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

class _NavigationSheet extends StatelessWidget {
  final double lat, lng;
  final String name;
  const _NavigationSheet(
      {required this.lat, required this.lng, required this.name});

  @override
  Widget build(BuildContext context) {
    final restArea = _isRestArea(name);
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
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/tmap_logo.webp'),
              label: '티맵',
              subtitle: restArea ? '고속도로 휴게소는 티맵 안내를 권장해요' : 'SK텔레콤',
              subtitleColor: restArea ? const Color(0xFFE07000) : Colors.grey,
              onTap: () => _launch(
                Uri(
                  scheme: 'tmap',
                  host: 'route',
                  queryParameters: {
                    'goalname': name,
                    'goaly': '$lat',
                    'goalx': '$lng',
                  },
                ).toString(),
                fallback: 'https://www.tmap.co.kr',
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/naver_logo.png'),
              label: '네이버 지도',
              subtitle: '네이버',
              popBeforeTap: false, // 주의 다이얼로그를 시트 위에 먼저 띄워야 함
              onTap: () => _tapNaver(context),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/kakaomap_logo.png'),
              label: '카카오내비',
              subtitle: '카카오',
              onTap: () => _launchKakaoNavi(name: name, lat: lat, lng: lng),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 네이버 지도 탭 — 첫 사용 시(또는 "다시 보지 않기" 전) 오안내 주의 안내.
  /// 휴게소·고속도로 목적지는 네이버의 "도착지 변경" 팝업 함정을 구체적으로 안내.
  Future<void> _tapNaver(BuildContext context) async {
    final box = Hive.box('settings');
    final restArea = _isRestArea(name);
    final warnKey = restArea ? _kNaverNavWarnRestOff : _kNaverNavWarnOff;
    final skip = box.get(warnKey, defaultValue: false) == true;

    if (!skip) {
      final content = restArea
          ? '네이버 지도에서 "도착지가 고속(화)도로에 위치합니다.\n'
              '주변 일반도로로 변경하시겠습니까?" 안내가 뜨면\n'
              '반드시 [도착지 유지]를 선택하세요.\n\n'
              '[도착지 변경]을 누르면 고속도로 밖 엉뚱한 곳으로\n'
              '안내될 수 있어요.'
          : '일부 주유소·충전소는 등록된 좌표가 실제 위치와 달라,\n'
              '네이버 지도 안내가 다른 곳으로 이어질 수 있어요.\n\n'
              '안내 시작 전에 목적지 이름과 위치를 꼭 확인해주세요.';
      final choice = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('목적지를 확인해주세요',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Text(
            content,
            style: const TextStyle(fontSize: 13.5, height: 1.55),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, 'never'),
              child: const Text('다시 보지 않기',
                  style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, 'close'),
              child: const Text('닫기',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (choice == null) return; // 바깥 탭 등으로 닫음 — 실행 안 함
      if (choice == 'never') await box.put(warnKey, true);
    }

    if (context.mounted) Navigator.pop(context); // 시트 닫기
    await _launch(
      'nmap://navigation?dlat=$lat&dlng=$lng&dname=${Uri.encodeComponent(name)}&appname=${AppConstants.packageName}',
      fallback: 'https://map.naver.com',
    );
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
