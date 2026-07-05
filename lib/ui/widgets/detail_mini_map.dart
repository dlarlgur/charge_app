import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation_util.dart';

/// 상세 화면용 미니맵 — 위치를 '사진처럼' 보여주는 정적 프리뷰.
///
/// 조잡함 방지 원칙:
///  · 제스처 전부 잠금(IgnorePointer) — 스크롤 중 지도에 손가락이 걸리는 문제 원천 차단
///  · 라이트모드 지도 — 인스턴스 부담 최소화
///  · 탭 = 길안내 시트 (보는 지도가 아니라 '행동으로 이어지는' 지도)
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
              // 지도 — 상호작용 완전 차단 (프리뷰 전용)
              IgnorePointer(
                child: NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: NLatLng(lat, lng),
                      zoom: 15.2,
                    ),
                    nightModeEnable: isDark,
                    liteModeEnable: true,
                    scrollGesturesEnable: false,
                    zoomGesturesEnable: false,
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
                ),
              ),
              // 테두리 (지도 위에 살짝)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                ),
              ),
              // 탭 → 길안내 시트
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showNavigationSheet(
                      context, lat: lat, lng: lng, name: name),
                ),
              ),
              // 우하단 '길안내' 칩 — 탭 가능함을 시각적으로 안내
              Positioned(
                right: 8,
                bottom: 8,
                child: IgnorePointer(
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
