import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation_util.dart';

/// 상세 화면용 미니맵 — 위치 프리뷰 + 확대/축소.
///
/// 조잡함 방지 원칙:
///  · 이동(팬)·회전·틸트 잠금 — 스크롤 중 지도가 딸려가는 문제 차단.
///  · 확대/축소는 우상단 +/- 버튼 전용 — 핀치는 스크롤뷰 안에서 포인터를
///    리스트와 나눠 갖으면 역줌·옆 팅김이 나서 OFF (실기기 리포트).
///  · 탭 = 길안내 시트 (지도 onMapTapped + 우하단 칩 양쪽)
///  · 높이는 폭 비례(46%)로 150~230dp 클램프 — 소형폰~태블릿 반응형
class DetailMiniMap extends StatefulWidget {
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
  State<DetailMiniMap> createState() => _DetailMiniMapState();
}

class _DetailMiniMapState extends State<DetailMiniMap> {
  NaverMapController? _controller;
  // 화면 전환(라우트 애니메이션)이 끝난 뒤에 지도 생성 — 네이티브 서피스는 무조건
  // 흰색으로 태어나는데(SDK가 초기색 미노출), 전환 중 생성되면 다크모드에서 흰
  // 번쩍임이 가장 크게 보임. 전환 후 생성 + 테마색 커버 페이드로 이중 방어.
  bool _mountMap = false;
  // 커버 해제는 onMapReady 가 아니라 '타일이 실제로 그려진 뒤' — ready 시점엔 아직
  // 흰 바탕이라 즉시 페이드하면 흰색이 드러남(실기기 리포트). ready + 지연 후 해제.
  bool _revealMap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 320), () {
        if (mounted) setState(() => _mountMap = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0);

    return LayoutBuilder(builder: (context, constraints) {
      final h = (constraints.maxWidth * 0.46).clamp(150.0, 230.0);
      return SizedBox(
        height: h,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 지도 — 제스처 전부 잠금(줌은 +/- 버튼). 탭하면 길안내.
              if (_mountMap)
                NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: NLatLng(widget.lat, widget.lng),
                      zoom: 14.3,
                    ),
                    minZoom: 11,
                    maxZoom: 18,
                    nightModeEnable: isDark,
                    scrollGesturesEnable: false,
                    // 핀치 줌 OFF — 스크롤뷰 안에서 두 손가락 중 하나를 리스트가
                    // 가로채면 역줌·옆 팅김이 발생(실기기 리포트). 줌은 +/- 버튼 전용
                    // (컨트롤러 줌이라 중심 고정, 안 튐).
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
                      position: NLatLng(widget.lat, widget.lng),
                    ));
                    if (mounted) setState(() => _controller = controller);
                    // 타일 렌더 완료 대기 후 커버 해제 — ready 직후엔 아직 흰 바탕이라
                    // 즉시 페이드하면 흰색이 드러남(실기기 리포트).
                    Future.delayed(const Duration(milliseconds: 550), () {
                      if (mounted) setState(() => _revealMap = true);
                    });
                  },
                  onMapTapped: (_, __) => showNavigationSheet(context,
                      lat: widget.lat, lng: widget.lng, name: widget.name),
                ),
              // 초기화 커버 — 네이티브 지도 서피스가 흰색으로 먼저 그려져 다크모드에서
              // 흰 화면이 번쩍하는 문제 가림. 지도 준비되면 페이드아웃.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _revealMap ? 0 : 1,
                    duration: const Duration(milliseconds: 350),
                    child: Container(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      alignment: Alignment.center,
                      child: Icon(Icons.map_outlined,
                          size: 22,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : const Color(0xFFB6C2CF)),
                    ),
                  ),
                ),
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
              // 우상단 +/- 줌 버튼 — 컨트롤러 준비 후 표시 (패키지 제공 위젯, 다크 연동)
              if (_controller != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: NaverMapZoomControlWidget(
                    mapController: _controller,
                    nightMode: isDark,
                    size: 34,
                    roundness: 10,
                  ),
                ),
              // 우하단 '길안내' 칩 — 지도 탭과 동일 동작의 실제 버튼
              Positioned(
                right: 8,
                bottom: 8,
                child: GestureDetector(
                  onTap: () => showNavigationSheet(context,
                      lat: widget.lat, lng: widget.lng, name: widget.name),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.accent,
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
