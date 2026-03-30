import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';

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

Future<void> showViaWaypointNavigationSheet(
  BuildContext context, {
  required double originLat,
  required double originLng,
  // originName은 네비 앱에 표시용으로 들어가는데,
  // 값이 안 넘어올 때 '출발지' 같은 기본 문자열이 들어가면
  // 사용자가 인지하기에 잘못된 정보로 보일 수 있어 빈 문자열로 처리한다.
  String originName = '',
  required double waypointLat,
  required double waypointLng,
  required String waypointName,
  required double destinationLat,
  required double destinationLng,
  required String destinationName,
}) async {
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ViaWaypointNavigationSheet(
      originLat: originLat,
      originLng: originLng,
      originName: originName,
      waypointLat: waypointLat,
      waypointLng: waypointLng,
      waypointName: waypointName,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationName: destinationName,
    ),
  );
}

class _NavigationSheet extends StatelessWidget {
  final double lat, lng;
  final String name;
  const _NavigationSheet({required this.lat, required this.lng, required this.name});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('길찾기 앱 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/naver_logo.png'),
              label: '네이버 지도',
              subtitle: '네이버',
              onTap: () => _launch(
                context,
                'nmap://navigation?dlat=$lat&dlng=$lng&dname=${Uri.encodeComponent(name)}&appname=${AppConstants.packageName}',
                fallback: 'https://map.naver.com',
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/kakaomap_logo.png'),
              label: '카카오내비',
              subtitle: '카카오',
              onTap: () => _launch(
                context,
                'kakaonavi://navigate?ep=${lng}_${lat}&by=CAR',
                fallback: 'https://kakaonavi.kakao.com',
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/tmap_logo.webp'),
              label: '티맵',
              subtitle: 'SK텔레콤',
              onTap: () => _launch(
                context,
                'tmap://route?goalname=${Uri.encodeComponent(name)}&goaly=$lat&goalx=$lng',
                fallback: 'https://www.tmap.co.kr',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, {required Widget icon, required String label, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: icon,
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _launch(BuildContext context, String url, {required String fallback}) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(Uri.parse(fallback), mode: LaunchMode.externalApplication);
    }
  }
}

class _ViaWaypointNavigationSheet extends StatelessWidget {
  final double originLat, originLng;
  final String originName;
  final double waypointLat, waypointLng;
  final String waypointName;
  final double destinationLat, destinationLng;
  final String destinationName;

  const _ViaWaypointNavigationSheet({
    required this.originLat,
    required this.originLng,
    required this.originName,
    required this.waypointLat,
    required this.waypointLng,
    required this.waypointName,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationName,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('경유 길찾기 앱 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/naver_logo.png'),
              label: '네이버 지도',
              subtitle: '네이버',
              onTap: () => _launch(
                context,
                'nmap://route/car?slat=$originLat&slng=$originLng&sname=${Uri.encodeComponent(originName)}'
                '&v1lat=$waypointLat&v1lng=$waypointLng&v1name=${Uri.encodeComponent(waypointName)}'
                '&dlat=$destinationLat&dlng=$destinationLng&dname=${Uri.encodeComponent(destinationName)}'
                '&appname=${AppConstants.packageName}',
                fallback: 'https://map.naver.com',
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/kakaomap_logo.png'),
              label: '카카오내비',
              subtitle: '카카오',
              onTap: () => _launch(
                context,
                // kakaomap://route 사용 (lat,lng 순서, 쉼표 구분)
                'kakaomap://route?sp=$originLat,$originLng&sname=${Uri.encodeComponent(originName)}'
                '&ep=$destinationLat,$destinationLng&ename=${Uri.encodeComponent(destinationName)}'
                '&via1=$waypointLat,$waypointLng&by=CAR',
                fallback: 'https://map.kakao.com',
              ),
            ),
            _navItem(
              context,
              icon: const _NavAssetIcon('assets/nav/tmap_logo.webp'),
              label: '티맵',
              subtitle: 'SK텔레콤',
              onTap: () => _launch(
                context,
                // 경유지 파라미터: viaX1/viaY1/vianame1 (번호형 필수)
                'tmap://route?startX=$originLng&startY=$originLat&startname=${Uri.encodeComponent(originName)}'
                '&goalname=${Uri.encodeComponent(destinationName)}&goaly=$destinationLat&goalx=$destinationLng'
                '&viaX1=$waypointLng&viaY1=$waypointLat&vianame1=${Uri.encodeComponent(waypointName)}',
                fallback: 'https://www.tmap.co.kr',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, {required Widget icon, required String label, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: icon,
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _launch(BuildContext context, String url, {required String fallback}) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(Uri.parse(fallback), mode: LaunchMode.externalApplication);
    }
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
