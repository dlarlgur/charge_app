import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';

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
              onTap: () => _launch(
                'nmap://navigation?dlat=$lat&dlng=$lng&dname=${Uri.encodeComponent(name)}&appname=${AppConstants.packageName}',
                fallback: 'https://map.naver.com',
              ),
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

  Widget _navItem(
    BuildContext context, {
    required Widget icon,
    required String label,
    required String subtitle,
    Color subtitleColor = Colors.grey,
    required VoidCallback onTap,
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
        Navigator.pop(context);
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
