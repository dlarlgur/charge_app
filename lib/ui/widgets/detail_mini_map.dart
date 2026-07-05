import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation_util.dart';

/// 상세 화면용 미니맵 — 위치 프리뷰 + 핀치 줌.
///
/// 조잡함 방지 원칙:
///  · 이동(팬)·회전·틸트 잠금 — 스크롤 중 지도가 딸려가는 문제 차단.
///    줌(핀치·더블탭)만 허용: 확대해 입구 위치, 축소해 동네 맥락 확인 (사용자 피드백).
///  · 탭 = 길안내 시트 (지도 onMapTapped + 우하단 칩 양쪽)
///  · 높이는 폭 비례(38%)로 130~190dp 클램프 — 소형폰~태블릿 반응형
class DetailMiniMap extends StatelessWidget {
  final double lat;
  final double lng;
  final String name;

  /// 길안내 버튼/마커 포인트 색 — 주유 파랑 / EV 초록.
  final Color accent;

  const DetailMiniMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.name,
    this.accent = AppColors.gasBlue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0);

    return LayoutBuilder(builder: (context, constraints) {
      final h = (constraints.maxWidth * 0.38).clamp(130.0, 190.0);
      return SizedBox(
        height: h,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 지도 — 줌(핀치·더블탭)만 허용, 이동·회전·틸트 잠금. 탭하면 길안내.
              NaverMap(
                options: NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: NLatLng(lat, lng),
                    zoom: 14.3, // 동네 맥락이 보이는 배율 (15.2는 과확대 피드백)
                  ),
                  minZoom: 11,
                  maxZoom: 18,
                  nightModeEnable: isDark,
                  scrollGesturesEnable: false,
                  zoomGesturesEnable: true,
                  rotationGesturesEnable: false,
                  tiltGesturesEnable: false,
                  stopGesturesEnable: false,
                  scaleBarEnable: false,
                  indoorLevelPickerEnable: false,
                  locationButtonEnable: false,
                ),
                onMapReady: (controller) {
                  controller.addOverlay(NMarker(
                    id: 'detail_mini_marker',
                    position: NLatLng(lat, lng),
                  ));
                },
                onMapTapped: (_, __) => showNavigationSheet(
                    context, lat: lat, lng: lng, name: name),
              ),
              // 테두리 (지도 위에 살짝) — 터치는 지도로 통과
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                  ),
                ),
              ),
              // 우하단 '길안내' 칩 — 지도 탭과 동일 동작의 실제 버튼
              Positioned(
                right: 8,
                bottom: 8,
                child: GestureDetector(
                  onTap: () => showNavigationSheet(
                      context, lat: lat, lng: lng, name: name),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded,
                            size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('길안내',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
