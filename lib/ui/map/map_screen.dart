import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/helpers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/station_alias_service.dart';
import '../../providers/providers.dart';
import '../detail/ev_detail_screen.dart';
import '../detail/gas_detail_screen.dart';
import '../filter/ev_filter_sheet.dart';
import '../filter/gas_filter_sheet.dart';
import '../widgets/gas_station_map_badge.dart';
import '../widgets/shared_widgets.dart';

// HomeScreen의 PopScope가 시트 닫기와 앱종료 토스트를 동시에 띄우는 걸 막기 위한 플래그
final ValueNotifier<bool> mapSheetOpen = ValueNotifier(false);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  NaverMapController? _mapController;
  late bool _showGas;
  late bool _showEv;
  dynamic _selectedStation;
  // 같은 GPS 에 여러 마커(아파트 단지 등) 클러스터 클릭 시 보여줄 목록.
  // List<GasStation | EvStation> — 같은 (lat,lng) 좌표(소수점 4자리=약 11m 단위) 그룹.
  List<dynamic>? _selectedCluster;
  bool _showSearchHere = false;
  bool _mapReady = false;
  // NaverMap(PlatformView)을 캐시 — 부모 setState 가 잦아도 동일 위젯 인스턴스라
  // NaverMap 이 rebuild 되지 않아 제스처/줌이 끊기지 않음.
  // isDark 변경 시에만 재생성 → NaverMap 의 _updateOptionsIfNeeded 가 nightMode
  // 라이브 업데이트 (PlatformView 재생성 없음).
  Widget? _cachedMap;
  bool? _cachedMapIsDark;
  int _markersGeneration = 0;
  final Map<String, NClusterableMarker> _markerRefs = {};
  // 줌 기반 네이티브 클러스터링용 원형 아이콘 (개수는 캡션으로 따로 그림).
  // 동기 clusterMarkerBuilder 안에서 await 불가 → 타입별 3종을 미리 래스터해 둠.
  NOverlayImage? _clusterIconGas;
  NOverlayImage? _clusterIconEv;
  NOverlayImage? _clusterIconMixed;
  // 검색한 장소를 표시하는 핀(역삼각 빨강) — 스테이션 마커와 별개 타입(marker)이라
  // 클러스터링/마커 갱신에 휩쓸리지 않음.
  NMarker? _searchMarker;
  Timer? _markerDebounce;
  double? _lastMinGasPrice;
  bool _isLocating = false;
  bool _isAtMyLocation = false;
  bool _suppressCameraChange = false;
  DraggableScrollableController? _sheetController;

  // ─── 이 지역 목록 시트 ───
  // 상세/클러스터 시트(_sheetController)와 별개의 컨트롤러 — 두 시트가 동시에
  // 안 뜨므로 충돌 없음. 정렬 토글은 로컬 state.
  final DraggableScrollableController _listSheetController =
      DraggableScrollableController();
  // 정렬: true=가격순, false=거리순. 기본값은 vehicleType 따라 _resetListSort 에서 결정.
  bool _listSortByPrice = true;
  bool _listSortInitialized = false;

  // 검색
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _searchHistory = [];
  bool _isSearchLoading = false;

  // ── 검색 기록 helpers ──
  List<Map<String, dynamic>> _loadHistory() {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final raw = box.get(AppConstants.keySearchHistory);
      if (raw is List) {
        return raw.whereType<String>().map((s) {
          final m = jsonDecode(s);
          return Map<String, dynamic>.from(m as Map);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  void _saveToHistory(Map<String, dynamic> place) {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final current = _loadHistory();
      current.removeWhere((h) => h['name'] == place['name']);
      current.insert(0, place);
      final trimmed = current.take(15).toList();
      box.put(AppConstants.keySearchHistory,
          trimmed.map((m) => jsonEncode(m)).toList());
      setState(() => _searchHistory = trimmed);
    } catch (_) {}
  }

  void _removeFromHistory(String name) {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final current = _loadHistory();
      current.removeWhere((h) => h['name'] == name);
      box.put(AppConstants.keySearchHistory,
          current.map((m) => jsonEncode(m)).toList());
      setState(() => _searchHistory = current);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _searchHistory = _loadHistory();
    final vehicleType = ref.read(settingsProvider).vehicleType;
    if (vehicleType == VehicleType.gas) {
      _showGas = true;
      _showEv = false;
    } else if (vehicleType == VehicleType.ev) {
      _showGas = false;
      _showEv = true;
    } else {
      final box = Hive.box(AppConstants.settingsBox);
      _showGas = box.get(AppConstants.keyMapShowGas, defaultValue: true);
      _showEv = box.get(AppConstants.keyMapShowEv, defaultValue: true);
    }
  }

  @override
  void dispose() {
    _markerDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _sheetController?.dispose();
    _listSheetController.dispose();
    super.dispose();
  }

  /// 목록 시트 정렬 기본값 — 주유=가격순, 충전=거리순. 둘 다 보이면 주유 기준(가격순).
  /// 첫 1회만 vehicleType 기준으로 세팅하고, 이후엔 사용자 토글 유지.
  void _ensureListSortDefault() {
    if (_listSortInitialized) return;
    _listSortInitialized = true;
    // 충전만 보이는 모드면 거리순, 그 외(주유 포함)는 가격순.
    _listSortByPrice = !(_showEv && !_showGas);
  }

  void _selectStation(dynamic station) {
    _sheetController?.dispose();
    _sheetController = DraggableScrollableController();
    mapSheetOpen.value = true;
    setState(() {
      _selectedStation = station;
      _selectedCluster = null;
    });
  }

  /// 같은 GPS 에 여러 마커가 있을 때(아파트 단지 등) 클릭 시 호출.
  /// 목록 시트로 전환 — 사용자가 1개 선택하면 _selectStation 으로 단일 상세 전환.
  void _selectCluster(List<dynamic> stations) {
    _sheetController?.dispose();
    _sheetController = DraggableScrollableController();
    mapSheetOpen.value = true;
    setState(() {
      _selectedStation = null;
      _selectedCluster = stations;
    });
  }

  Future<void> _dismissSheet() async {
    final prev = _selectedStation;
    mapSheetOpen.value = false;
    setState(() {
      _selectedStation = null;
      _selectedCluster = null;
    });
    _sheetController?.dispose();
    _sheetController = null;
    await _restoreMarkerIcon(prev, _lastMinGasPrice);
  }

  /// 좌표 그룹화 키 — 소수점 4자리 일치(약 11m) 기준.
  /// 환경부 EV API 가 같은 아파트 동을 같은 GPS 로 등록하는 케이스 커버.
  String _clusterKey(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// 충전소/주유소 목록을 클러스터 그룹으로 묶음. 1개짜리는 그대로, 2개+ 는
  /// 단일 클러스터 항목으로.
  Map<String, List<T>> _groupByCluster<T>(List<T> items, NLatLng Function(T) coord) {
    final map = <String, List<T>>{};
    for (final it in items) {
      final c = coord(it);
      final key = _clusterKey(c.latitude, c.longitude);
      map.putIfAbsent(key, () => <T>[]).add(it);
    }
    return map;
  }

  void _scheduleUpdateMarkers() {
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 80), _updateMarkers);
  }

  void _clearMarkers() {
    _markerDebounce?.cancel();
    _markersGeneration++;
    _markerRefs.clear();
    _mapController?.clearOverlays(type: NOverlayType.clusterableMarker);
    // 필터 변경 등으로 마커가 전부 폐기될 때 — 다음 표시 셋과 키가 거의 안 겹치므로
    // 배지 아이콘 캐시도 같이 비워 메모리 회수. 첫 진입에만 재 raster 비용 있음.
    _badgeIconCache.clear();
    _badgeIconLru.clear();
  }

  void _setShowGas(bool value) {
    setState(() => _showGas = value);
    if (ref.read(settingsProvider).vehicleType == VehicleType.both) {
      Hive.box(AppConstants.settingsBox).put(AppConstants.keyMapShowGas, value);
    }
    _updateMarkers();
  }

  void _setShowEv(bool value) {
    setState(() => _showEv = value);
    if (ref.read(settingsProvider).vehicleType == VehicleType.both) {
      Hive.box(AppConstants.settingsBox).put(AppConstants.keyMapShowEv, value);
    }
    _updateMarkers();
  }

  void _moveToMyLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final streamed = ref.read(locationStreamProvider).valueOrNull;
      ({double lat, double lng})? loc = streamed;
      if (loc == null) {
        final pos = await LocationService().getFreshPosition();
        if (pos == null) return;
        loc = (lat: pos.latitude, lng: pos.longitude);
      }
      final target = NLatLng(loc.lat, loc.lng);
      _suppressCameraChange = true;
      _mapController?.updateCamera(NCameraUpdate.withParams(target: target, zoom: 14));
      final overlay = _mapController?.getLocationOverlay();
      overlay?.setIsVisible(true);
      overlay?.setPosition(target);
      if (mounted) setState(() { _isAtMyLocation = true; _showSearchHere = false; });
      // 애니메이션 완료 후 플래그 해제 (애니메이션 중 onCameraChange 여러 번 발동)
      Future.delayed(const Duration(milliseconds: 800), () {
        _suppressCameraChange = false;
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// 줌 레벨 → 대략적인 반경(m). 지도 초기화 시 bounds가 없을 때만 사용.
  static int _zoomToRadius(double zoom) {
    if (zoom >= 17) return 300;
    if (zoom >= 16) return 500;
    if (zoom >= 15) return 800;
    if (zoom >= 14) return 1500;
    if (zoom >= 13) return 3000;
    if (zoom >= 12) return 5000;
    if (zoom >= 11) return 10000;
    if (zoom >= 10.5) return 15000;
    if (zoom >= 10) return 20000;
    if (zoom >= 9) return 30000;
    return 50000;
  }

  /// 실제 지도 보이는 영역에서 중심~가장자리 거리(m) — 가로/세로 중 짧은 쪽 기준.
  /// 세로 화면에서 대각선을 쓰면 화면 밖 스테이션까지 포함되므로 짧은 축 사용.
  static int _boundsToRadius(NLatLngBounds bounds, NLatLng center) {
    const maxRadius = 50000;
    const earthR = 6371000.0;
    final ne = bounds.northEast;
    final latRad = center.latitude * math.pi / 180;
    // 수직 반경 (중심 → 북쪽 가장자리)
    final vertDist = earthR * ((ne.latitude - center.latitude) * math.pi / 180).abs();
    // 수평 반경 (중심 → 동쪽 가장자리)
    final horizDist = earthR * ((ne.longitude - center.longitude) * math.pi / 180).abs() * math.cos(latRad);
    final dist = math.min(vertDist, horizDist);
    return dist.clamp(200, maxRadius).toInt();
  }

  void _searchAtCurrentCenter() async {
    final controller = _mapController;
    if (controller == null) return;
    _clearMarkers(); // 탭 즉시 기존 마커 제거
    final pos = await controller.getCameraPosition();
    final bounds = await controller.getContentBounds();
    // bounds 는 일부 환경에서 null 일 수 있어 (analyzer 가 non-null 추론해도
    // 런타임엔 발생) — null 이면 zoom 기반 fallback
    final radius = bounds != null
        ? _boundsToRadius(bounds, pos.target)
        : _zoomToRadius(pos.zoom);
    ref.read(mapCenterProvider.notifier).state = (lat: pos.target.latitude, lng: pos.target.longitude);
    ref.read(mapRadiusProvider.notifier).state = radius;
    if (_selectedStation != null) await _dismissSheet();
    setState(() { _showSearchHere = false; });
  }

  // ─── 검색 ───
  // AI 탭과 동일한 lat/lng 결정 로직 — center 없으면 GPS fallback. 두 화면이
  // 같은 검색어에 동일 결과 반환하도록 보장.
  Timer? _searchDebounce;

  /// 입력마다 호출 — 디바운스해서 타이핑 멈춘 뒤에만 검색(키 입력당 네트워크 호출 폭주 방지).
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 320), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    _searchDebounce?.cancel(); // onSubmitted(엔터) 즉시 실행 시 대기 중 디바운스 취소
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearchLoading = true);
    try {
      final center = ref.read(mapCenterProvider);
      final loc = center == null ? await ref.read(locationProvider.future) : null;
      final lat = center?.lat ?? loc?.lat;
      final lng = center?.lng ?? loc?.lng;
      final results = await ApiService().searchPlaces(query.trim(), lat: lat, lng: lng);
      if (mounted) setState(() { _searchResults = results; _isSearchLoading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('[map-search] searchPlaces 실패: $e');
      if (mounted) setState(() { _searchResults = []; _isSearchLoading = false; });
    }
  }

  void _moveToPlace(Map<String, dynamic> place) {
    _saveToHistory(place);
    final lat = (place['lat'] as num).toDouble();
    final lng = (place['lng'] as num).toDouble();
    final name = (place['name'] ?? '').toString();
    // 이동 애니메이션 중 onCameraChange 연쇄로 핀이 곧장 지워지거나 줌이 튀는 것 방지.
    _suppressCameraChange = true;
    _mapController?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(lat, lng),
      zoom: 14,
    )..setAnimation(
        animation: NCameraAnimation.easing,
        duration: const Duration(milliseconds: 400),
      ));
    ref.read(mapCenterProvider.notifier).state = (lat: lat, lng: lng);
    // 검색 위치에 빨강 핀 + 장소명 캡션. 주변 주유/충전소는 center 갱신으로 재조회됨.
    _setSearchMarker(lat, lng, name);
    setState(() {
      _isSearchMode = false;
      _searchResults = [];
      _showSearchHere = false;
    });
    _searchController.clear();
    // 이동 애니메이션이 끝난 뒤부터 사용자 제스처를 받도록 플래그 해제.
    Future.delayed(const Duration(milliseconds: 650), () {
      _suppressCameraChange = false;
    });
  }

  /// 검색한 장소를 가리키는 빨강 핀 마커(+ 이름 캡션)를 찍는다.
  /// 스테이션 마커와 다른 색/모양으로 "여기 검색함" 을 분명히 보여줌.
  Future<void> _setSearchMarker(double lat, double lng, String name) async {
    final c = _mapController;
    if (c == null) return;
    if (_searchMarker != null) {
      await c.deleteOverlay(_searchMarker!.info);
      _searchMarker = null;
    }
    // 이름 알약을 핀과 한 이미지로 그림 — 네이티브 캡션(투박한 폰트/외곽선) 대신
    // Flutter 폰트로 깔끔하게. 가변 길이라 TextPainter 로 실제 폭을 재서 캔버스 산정.
    const double pinH = 44, pinW = 44, gap = 3;
    final hasName = name.isNotEmpty;
    // fromWidget 래스터는 앱 테마(Pretendard)를 상속 못 받아 시스템 폰트로 폴백됨 →
    // fontFamily 명시해 앱 글씨와 통일.
    const nameStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13, fontWeight: FontWeight.w700,
      color: Color(0xFF1F2937), height: 1.15,
    );
    double pillW = 0, pillH = 0;
    if (hasName) {
      final tp = TextPainter(
        text: TextSpan(text: name, style: nameStyle),
        maxLines: 1, textDirection: TextDirection.ltr,
      )..layout();
      // 좌우 패딩 11*2 + 여유 4 — 텍스트폭과 딱 맞아 반올림으로 말줄임 뜨던 것 방지.
      pillW = (tp.width + 26).clamp(34, 260).toDouble();
      pillH = tp.height + 10; // 상하 패딩 5*2
    }
    final canvasW = math.max(pinW, hasName ? pillW : pinW);
    // +4: TextPainter 높이와 실제 위젯 렌더 높이의 반올림 차이로 인한 2px 오버플로 방지.
    final canvasH = (hasName ? pillH + gap + pinH : pinH) + 4;

    final icon = await NOverlayImage.fromWidget(
      widget: _SearchPin(
        name: name, nameStyle: nameStyle, pillWidth: pillW,
        canvasWidth: canvasW, canvasHeight: canvasH,
      ),
      size: Size(canvasW, canvasH),
      context: context,
    );
    if (!mounted) return;
    final marker = NMarker(
      id: 'search_pin',
      position: NLatLng(lat, lng),
      icon: icon,
      anchor: const NPoint(0.5, 1.0), // 핀 끝(이미지 하단 중앙)이 좌표를 가리키도록
      // 다른 마커에 가려지지 않게 — 강제 노출 + 충돌해도 안 숨김.
      isForceShowIcon: true,
      isHideCollidedMarkers: false,
    );
    // 스테이션 마커보다 위에 그려지도록 zIndex 상향.
    marker.setZIndex(1000000);
    _searchMarker = marker;
    await c.addOverlay(marker);
  }

  // ─── 필터 열기 ───
  void _openFilter() {
    final vehicleType = ref.read(settingsProvider).vehicleType;
    if (vehicleType == VehicleType.gas || (_showGas && !_showEv)) {
      GasFilterSheet.show(context);
    } else if (vehicleType == VehicleType.ev || (_showEv && !_showGas)) {
      EvFilterSheet.show(context);
    } else {
      _showFilterChoiceSheet();
    }
  }

  void _showFilterChoiceSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('필터 선택', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.gasBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.local_gas_station_rounded, color: AppColors.gasBlue, size: 20),
              ),
              title: const Text('주유소 필터'),
              onTap: () { Navigator.pop(context); GasFilterSheet.show(context); },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.evGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.ev_station_rounded, color: AppColors.evGreen, size: 20),
              ),
              title: const Text('충전소 필터'),
              onTap: () { Navigator.pop(context); EvFilterSheet.show(context); },
            ),
          ],
        ),
      ),
    );
  }

  // ─── NaverMap 콜백 (위젯 캐시용 — 메서드 참조라 인스턴스가 안정적) ───
  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    const defaultZoom = 14.0;
    ref.read(mapRadiusProvider.notifier).state = _zoomToRadius(defaultZoom);
    ref.read(locationProvider.future).then((loc) {
      if (loc != null) {
        controller.updateCamera(NCameraUpdate.withParams(
          target: NLatLng(loc.lat, loc.lng),
          zoom: defaultZoom,
        ));
        ref.read(mapCenterProvider.notifier).state = (lat: loc.lat, lng: loc.lng);
        final overlay = controller.getLocationOverlay();
        overlay.setIsVisible(true);
        overlay.setPosition(NLatLng(loc.lat, loc.lng));
        _updateMarkers();
      }
    });
    _mapReady = true;
    _precacheBrandLogos();
    _buildClusterIcons();
    _updateMarkers();
  }

  void _onCameraChange(NCameraUpdateReason reason, bool animated) {
    if (_suppressCameraChange) return;
    // 사용자가 직접 지도를 확대/축소·이동하면 검색 핀을 거둠 (이동 직후 1회 표시용).
    if (_searchMarker != null &&
        (reason == NCameraUpdateReason.gesture ||
            reason == NCameraUpdateReason.control)) {
      _mapController?.deleteOverlay(_searchMarker!.info);
      _searchMarker = null;
    }
    // 값이 이미 원하는 상태면 setState 스킵 — 카메라 이동 중 rebuild 폭주 방지
    if (_mapReady && !_isSearchMode && (!_showSearchHere || _isAtMyLocation)) {
      setState(() {
        _showSearchHere = true;
        _isAtMyLocation = false;
      });
    }
  }

  void _onMapTapped(NPoint point, NLatLng latLng) {
    if (_isSearchMode) {
      setState(() {
        _isSearchMode = false;
        _searchResults = [];
        _searchController.clear();
      });
    } else if (_selectedStation != null) {
      _dismissSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vehicleType = ref.watch(settingsProvider).vehicleType;

    ref.listen(mapGasStationsProvider, (prev, next) {
      if (next is AsyncLoading && prev is AsyncData) _clearMarkers();
      else if (next is AsyncData) _scheduleUpdateMarkers();
    });
    ref.listen(mapEvStationsProvider, (prev, next) {
      if (next is AsyncLoading && prev is AsyncData) _clearMarkers();
      else if (next is AsyncData) _scheduleUpdateMarkers();
    });
    // 실시간 위치 스트림 → 파란 점 업데이트
    ref.listen(locationStreamProvider, (_, next) {
      next.whenData((loc) {
        final overlay = _mapController?.getLocationOverlay();
        overlay?.setIsVisible(true);
        overlay?.setPosition(NLatLng(loc.lat, loc.lng));
      });
    });
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.vehicleType != next.vehicleType) {
        setState(() {
          if (next.vehicleType == VehicleType.gas) {
            _showGas = true; _showEv = false;
          } else if (next.vehicleType == VehicleType.ev) {
            _showGas = false; _showEv = true;
          } else {
            _showGas = true; _showEv = true;
          }
        });
        _updateMarkers();
      }
    });

    // isDark 가 바뀐 경우만 재생성 (다크모드 토글 → nightMode 반영).
    // 그 외 setState 는 캐시 사용 → 제스처/줌 끊김 없음.
    if (_cachedMap == null || _cachedMapIsDark != isDark) {
      _cachedMapIsDark = isDark;
      _cachedMap = NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: const NCameraPosition(
          target: NLatLng(37.5665, 126.9780),
          zoom: 14,
        ),
        nightModeEnable: isDark,
        locationButtonEnable: false,
        consumeSymbolTapEvents: false,
        // 평면 지도라 틸트 불필요 + 수직 핀치줌이 틸트 제스처에 먹히는 것 방지.
        tiltGesturesEnable: false,
      ),
      // forceHybridComposition 제거 → 기본 TLHC(텍스처) 합성 경로 사용.
      // 과거 Flutter 3.24.3 의 엔진 회귀(translateMotionEvent, flutter#157463)로
      // TLHC 에서 멀티터치(핀치줌)가 깨져 전체 HC 를 강제했었으나, 현재 Flutter 3.38.5
      // 에선 해당 회귀가 해소됨. 강제 HC 는 팬/줌마다 텍스처를 통째 복사해 버벅임의
      // 주원인이라 제거 — 핀치줌이 정상이면 그대로 두고, 깨지면 forceHybridComposition:
      // true 로 되돌릴 것.
      // 줌 기반 클러스터링 — 줌아웃 시 가까운 마커를 지역별 원(개수)으로 병합,
      // 확대하면 개별 마커로 분리. 렌더 마커 수가 급감해 팬/줌이 부드러워짐.
      clusterOptions: NaverMapClusteringOptions(
        // 클러스터링이 동작할 줌 범위. 초기 줌(14)에선 개별 마커 그대로 보이고,
        // 한 단계 줌아웃(≤13)하면 지역별 원으로 묶이게 — 첫화면 묶임/과도한 줌아웃의 중간.
        enableZoomRange: const NInclusiveRange(0, 13),
        // 화면상 거리 기준 병합. 줌아웃일수록 더 넓게 묶어 개수를 확 줄임.
        mergeStrategy: const NClusterMergeStrategy(
          willMergedScreenDistance: {
            NInclusiveRange(0, 9): 120,   // 광역(시/도) — 크게 묶음
            NInclusiveRange(10, 12): 90,  // 시군구 단위
          },
          maxMergeableScreenDistance: 120,
        ),
        clusterMarkerBuilder: _buildClusterMarker,
      ),
      onMapReady: _onMapReady,
      onCameraChange: _onCameraChange,
      onMapTapped: _onMapTapped,
    );
    }

    return Scaffold(
      // 검색창은 상단 고정 — 키보드가 떴다 닫힐 때 지도(PlatformView)가 리사이즈되며
      // 줌이 튀어 보이는 깜빡임 방지. 키보드는 지도 위에 겹쳐 뜨게 둠.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ─── 네이버 지도 ───
          // RepaintBoundary 로 지도 레이어 격리 — 시트 열고 닫기 등 다른 UI 변화 시
          // 지도까지 같이 repaint 안 되도록. 마커 update 도 별도 cached layer.
          RepaintBoundary(child: _cachedMap!),

          // ─── 상단 오버레이 ───
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12, right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 검색창
                _buildSearchBar(isDark),
                const SizedBox(height: 8),
                // 탭 + 필터
                _buildTabRow(isDark, vehicleType),
                // 검색 결과
                if (_isSearchMode)
                  _buildSearchResults(isDark),
                // 이 지역 검색 버튼
                if (_showSearchHere && !_isSearchMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(child: _buildSearchHereButton(isDark)),
                  ),
              ],
            ),
          ),

          // ─── 현재 위치 버튼 ───
          Positioned(
            right: 16,
            // 목록 시트 peek(~0.12) 위로 올려 가리지 않게. 상세 시트 떠 있으면 더 높게.
            bottom: MediaQuery.of(context).padding.bottom +
                (_selectedStation != null
                    ? 200
                    : (_selectedCluster == null && !_isSearchMode
                        ? MediaQuery.of(context).size.height * 0.12 + 20
                        : 24)),
            child: GestureDetector(
              onTap: _moveToMyLocation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (_isLocating || _isAtMyLocation)
                      ? AppColors.evGreen
                      : (isDark ? AppColors.darkBg : Colors.white),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: _isLocating
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: Center(
                          child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        ),
                      )
                    : Icon(Icons.my_location_rounded, size: 22,
                        color: (_isAtMyLocation)
                            ? Colors.white
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
              ),
            ),
          ),

          // ─── 이 지역 목록 시트 ───
          // 상세 시트/클러스터 시트가 떠 있지 않을 때만 — 겹침 방지.
          // 검색 모드 중엔 상단 결과 패널에 집중하도록 숨김.
          if (_selectedStation == null &&
              _selectedCluster == null &&
              !_isSearchMode)
            _buildAreaListSheet(isDark, vehicleType),

          // ─── 하단 상세 시트 ───
          if (_selectedCluster != null && _sheetController != null)
            PopScope(
              canPop: false,
              onPopInvokedWithResult: (_, __) => _dismissSheet(),
              child: _buildClusterListSheet(_selectedCluster!, isDark),
            ),
          if (_selectedStation is GasStation && _sheetController != null)
            PopScope(
              canPop: false,
              onPopInvokedWithResult: (_, __) => _dismissSheet(),
              child: _buildGasDetailSheet(_selectedStation as GasStation, isDark),
            ),
          if (_selectedStation is EvStation && _sheetController != null)
            PopScope(
              canPop: false,
              onPopInvokedWithResult: (_, __) => _dismissSheet(),
              child: _buildEvDetailSheet(_selectedStation as EvStation, isDark),
            ),
        ],
      ),
    );
  }

  // ─── 검색바 ───
  Widget _buildSearchBar(bool isDark) {
    return GestureDetector(
      onTap: _isSearchMode ? null : () => setState(() => _isSearchMode = true),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded, size: 20,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            const SizedBox(width: 8),
            Expanded(
              child: _isSearchMode
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '장소, 주소 검색',
                        border: InputBorder.none,
                        hintStyle: TextStyle(fontSize: 14,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87),
                      onChanged: _onSearchChanged,
                      onSubmitted: _performSearch,
                    )
                  : Text('장소, 주소 검색',
                      style: TextStyle(fontSize: 14,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            ),
            GestureDetector(
              onTap: _isSearchMode
                  ? () => setState(() {
                        _isSearchMode = false;
                        _searchResults = [];
                        _searchController.clear();
                      })
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _isSearchMode
                    ? Icon(Icons.close_rounded, size: 18,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)
                    : const SizedBox(width: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 탭 + 필터 행 ───
  Widget _buildTabRow(bool isDark, VehicleType vehicleType) {
    return Row(
      children: [
        // 필터 버튼
        GestureDetector(
          onTap: _openFilter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBg : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 15,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                const SizedBox(width: 4),
                Text('필터', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 주유 탭
        if (vehicleType != VehicleType.ev) ...[
          _buildTabChip(Icons.local_gas_station_rounded, '주유', _showGas,
              AppColors.gasBlue, isDark, () => _setShowGas(!_showGas)),
          if (vehicleType == VehicleType.both) const SizedBox(width: 6),
        ],
        // 충전 탭
        if (vehicleType != VehicleType.gas)
          _buildTabChip(Icons.electric_bolt_rounded, '충전', _showEv,
              AppColors.evGreen, isDark, () => _setShowEv(!_showEv)),
      ],
    );
  }

  Widget _buildTabChip(IconData icon, String label, bool active, Color color,
      bool isDark, VoidCallback onTap) {
    final fg = active
        ? Colors.white
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? color : (isDark ? AppColors.darkBg : Colors.white),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))],
          border: active ? null : Border.all(
              color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.2,
            )),
          ],
        ),
      ),
    );
  }

  // ─── 검색 결과 ───
  Widget _buildSearchResults(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: _isSearchLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          // 검색어 없음 → 최근 검색 기록
          : _searchController.text.trim().isEmpty
              ? _searchHistory.isEmpty
                  ? SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('장소명, 주소를 입력하세요',
                            style: TextStyle(fontSize: 13,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                          child: Row(
                            children: [
                              Text('최근 검색',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  Hive.box(AppConstants.settingsBox).delete(AppConstants.keySearchHistory);
                                  setState(() => _searchHistory = []);
                                },
                                child: Text('전체 삭제',
                                    style: TextStyle(fontSize: 11,
                                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                              ),
                            ],
                          ),
                        ),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _searchHistory.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
                          itemBuilder: (_, i) {
                            final h = _searchHistory[i];
                            return GestureDetector(
                              onTap: () => _moveToPlace(h),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                child: Row(
                                  children: [
                                    Icon(Icons.history_rounded, size: 15,
                                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(h['name'] ?? '',
                                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                                                  color: isDark ? Colors.white : Colors.black87),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if ((h['address'] ?? '').isNotEmpty)
                                            Text(h['address'],
                                                style: TextStyle(fontSize: 11,
                                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _removeFromHistory(h['name']?.toString() ?? ''),
                                      child: Icon(Icons.close_rounded, size: 14,
                                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    )
          : _searchResults.isEmpty
              ? SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('검색 결과가 없습니다',
                        style: TextStyle(fontSize: 13,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
                  itemBuilder: (_, i) {
                    final place = _searchResults[i];
                    final category = place['category']?.toString();
                    final dist = place['distance'];
                    final distStr = dist != null
                        ? formatDistance((dist as num).toDouble())
                        : null;
                    return GestureDetector(
                      onTap: () => _moveToPlace(place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded, size: 16,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(place['name'] ?? '',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.white : Colors.black87),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      if (category != null && category.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(category,
                                              style: TextStyle(fontSize: 11,
                                                  color: isDark ? AppColors.darkTextMuted : const Color(0xFF888888)),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                      if (distStr != null) ...[
                                        const SizedBox(width: 6),
                                        Text(distStr,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF1D6FE0)),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ],
                                  ),
                                  if ((place['address'] ?? '').isNotEmpty)
                                    Text(place['address'],
                                        style: TextStyle(fontSize: 11,
                                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // ─── 이 지역 검색 버튼 ───
  Widget _buildSearchHereButton(bool isDark) {
    return GestureDetector(
      onTap: _searchAtCurrentCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
          border: Border.all(color: AppColors.gasBlue.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 15, color: AppColors.gasBlue),
            const SizedBox(width: 5),
            Text('이 지역 검색',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gasBlue)),
          ],
        ),
      ),
    );
  }

  Future<void> _precacheBrandLogos() async {
    await GasStationMapBadge.precacheBrandImages(context);
  }

  // ─── 줌 기반 클러스터 원형 아이콘 (타입별 색) ───
  // 동기 clusterMarkerBuilder 안에서는 위젯 래스터(await)가 불가하므로,
  // 주유(파랑)·충전(초록)·혼합(인디고) 3종을 맵 준비 시 미리 만들어 둔다.
  // 개수 텍스트는 아이콘에 굽지 않고 네이티브 캡션으로 그려 클러스터마다 재래스터 0.
  Future<void> _buildClusterIcons() async {
    if (!mounted) return;
    Future<NOverlayImage> circle(Color color) => NOverlayImage.fromWidget(
          widget: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          size: const Size(44, 44),
          context: context,
        );
    final results = await Future.wait([
      circle(AppColors.gasBlue),
      circle(AppColors.evGreen),
      circle(AppColors.gasBlue), // 주유+충전 혼합도 파랑(주유 톤)
    ]);
    if (!mounted) return;
    _clusterIconGas = results[0];
    _clusterIconEv = results[1];
    _clusterIconMixed = results[2];
  }

  // 네이티브가 가까운 NClusterableMarker 들을 묶을 때마다 호출(동기).
  // children 의 'type' 태그 구성으로 주유/충전/혼합을 판정해 색을 정하고,
  // 개수는 캡션으로 표시. 탭하면 해당 위치로 줌인해 개별 마커가 드러나게 한다.
  void _buildClusterMarker(NClusterInfo info, NClusterMarker clusterMarker) {
    var hasGas = false, hasEv = false;
    for (final child in info.children) {
      final t = child.tags['type'];
      if (t == 'ev') {
        hasEv = true;
      } else {
        hasGas = true;
      }
      if (hasGas && hasEv) break;
    }
    final icon = (hasGas && hasEv)
        ? _clusterIconMixed
        : (hasEv ? _clusterIconEv : _clusterIconGas);
    if (icon != null) clusterMarker.setIcon(icon);
    clusterMarker.setCaption(NOverlayCaption(
      text: info.size.toString(),
      color: Colors.white,
      textSize: 13,
      haloColor: Colors.transparent,
    ));
    clusterMarker.setOnTapListener((_) async {
      final c = _mapController;
      if (c == null) return;
      final pos = await c.getCameraPosition();
      await c.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: clusterMarker.position,
          zoom: (pos.zoom + 2).clamp(0.0, 20.0),
        )..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 300),
          ),
      );
    });
  }

  // ─── 마커 배지 아이콘 캐시 ───
  // 키: 렌더 결과를 결정하는 모든 입력. 가격 동일하면 동일 비트맵 재사용.
  // 150개 마커 × widget→bitmap rasterize 비용 (각 10~30ms) 을 매 update 마다
  // 반복하던 것을 캐시 hit 시 0ms 로. 최대 _kBadgeCacheMax 항목 LRU 유지.
  static const int _kBadgeCacheMax = 400;
  final Map<String, NOverlayImage> _badgeIconCache = {};
  final List<String> _badgeIconLru = [];
  // 병렬 마커 빌드 중 같은 아이콘 key 의 동시 래스터를 1회로 합침(중복 raster 제거).
  final Map<String, Future<NOverlayImage>> _badgeIconInflight = {};

  // ─── 마커 배지 아이콘 (로고 + 가격/텍스트 카드 스타일) ───
  Future<NOverlayImage> _stationBadgeIcon({
    required String label,
    String? brand,
    String? stationName,
    bool isEv = false,
    bool isHighlighted = false,
    bool isCheapest = false,
  }) async {
    final key = '$label|$brand|$stationName|$isEv|$isHighlighted|$isCheapest';
    final cached = _badgeIconCache[key];
    if (cached != null) {
      _badgeIconLru.remove(key);
      _badgeIconLru.add(key);
      return cached;
    }
    final inflight = _badgeIconInflight[key];
    if (inflight != null) return inflight; // 동시 요청 → 진행 중 future 공유
    final future = () async {
      final Color borderColor = isHighlighted
          ? _kSelectedColor
          : (isCheapest ? const Color(0xFFEF4444) : const Color(0xFFDDDDDD));
      final Color textColor = isHighlighted
          ? _kSelectedColor
          : (isCheapest ? const Color(0xFFEF4444) : const Color(0xFF1a1a1a));
      final icon = await GasStationMapBadge.overlayImage(
        context,
        label: label,
        brand: brand,
        stationName: stationName,
        isEv: isEv,
        borderColor: borderColor,
        textColor: textColor,
        emphasizeBorder: isHighlighted,
      );
      _badgeIconCache[key] = icon;
      _badgeIconLru.add(key);
      if (_badgeIconLru.length > _kBadgeCacheMax) {
        final evict = _badgeIconLru.removeAt(0);
        _badgeIconCache.remove(evict);
      }
      return icon;
    }();
    _badgeIconInflight[key] = future;
    try {
      return await future;
    } finally {
      _badgeIconInflight.remove(key);
    }
  }

  /// 거리순 정렬된 목록에서 [maxCount]개를 균등 간격으로 추출.
  /// 넓은 반경 조회 시 중심 밀집 현상 없이 전 영역에 고르게 표시.
  static List<T> _spreadSample<T>(List<T> sorted, int maxCount) {
    if (sorted.length <= maxCount) return sorted;
    final step = sorted.length / maxCount;
    return List.generate(maxCount, (i) => sorted[(i * step).floor()]);
  }

  static const _kSelectedColor = Color(0xFF60A5FA); // light blue: 선택된 마커

  // ─── 마커 업데이트 ───
  Future<void> _updateMarkers() async {
    final controller = _mapController;
    if (controller == null) return;

    // gas / EV 가 따로 로딩 완료되며 두 번 그리는 더블 드로 방지.
    // 필요한 provider 가 아직 로딩 중이면 스킵 — 마지막에 끝나는 쪽이 재호출함.
    if (_showGas && ref.read(mapGasStationsProvider).isLoading) return;
    if (_showEv && ref.read(mapEvStationsProvider).isLoading) return;

    final gen = ++_markersGeneration;
    _markerRefs.clear();
    await controller.clearOverlays(type: NOverlayType.clusterableMarker);
    if (gen != _markersGeneration) return;

    final gasStations = _spreadSample<GasStation>(
      ref.read(mapGasStationsProvider).valueOrNull ?? <GasStation>[], 150,
    );
    final evStations = _spreadSample<EvStation>(
      ref.read(mapEvStationsProvider).valueOrNull ?? <EvStation>[], 150,
    );

    // 필터 변경 등으로 선택된 스테이션이 결과에서 사라지면 선택 해제
    if (_selectedStation != null) {
      final stillVisible = (_selectedStation is GasStation &&
              gasStations.any((s) => s.id == (_selectedStation as GasStation).id)) ||
          (_selectedStation is EvStation &&
              evStations.any((s) => s.statId == (_selectedStation as EvStation).statId));
      if (!stillVisible && mounted) setState(() => _selectedStation = null);
    }

    double? minGasPrice;
    if (_showGas && gasStations.isNotEmpty) {
      minGasPrice = gasStations.map((s) => s.price).reduce((a, b) => a < b ? a : b);
    }
    _lastMinGasPrice = minGasPrice;

    // ── 마커 빌드: 아이콘(위젯 래스터)을 병렬로 만들고 한 번에 addOverlayAll ──
    // 이전: 마커마다 `icon: await ...` + `addOverlay` 를 순차(최대 300×2 호출) → 첫 드로 잭.
    // 변경: 아이콘 Future 를 병렬로 만들고(캐시+in-flight 중복제거), 마커는 1회 배치 추가.
    final markerFutures = <Future<NClusterableMarker>>[];

    if (_showGas) {
      final gasGroups = _groupByCluster<GasStation>(
        gasStations, (s) => NLatLng(s.lat, s.lng),
      );
      gasGroups.forEach((keyc, group) {
        if (group.length == 1) {
          final s = group.first;
          final isCheapest = minGasPrice != null && s.price == minGasPrice;
          final isSelected = _selectedStation is GasStation &&
              (_selectedStation as GasStation).id == s.id;
          final label = s.priceText;
          final markerId = 'gas_${s.id}';
          final displayName = StationAliasService.resolveGas(s.id, s.name);
          markerFutures.add(() async {
            final marker = NClusterableMarker(
              id: markerId,
              position: NLatLng(s.lat, s.lng),
              tags: const {'type': 'gas'},
              icon: await _stationBadgeIcon(
                label: label, brand: s.brand, stationName: displayName,
                isHighlighted: isSelected, isCheapest: isCheapest,
              ),
            );
            marker.setOnTapListener((_) async {
              final prev = _selectedStation;
              if (prev is GasStation && prev.id == s.id) {
                await _dismissSheet();
                return;
              }
              await _restoreMarkerIcon(prev, _lastMinGasPrice);
              _selectStation(s);
              await _highlightMarker(markerId, label, brand: s.brand, stationName: displayName);
            });
            _markerRefs[markerId] = marker;
            return marker;
          }());
        } else {
          final first = group.first;
          final markerId = 'gas_cluster_$keyc';
          markerFutures.add(() async {
            final marker = NClusterableMarker(
              id: markerId,
              position: NLatLng(first.lat, first.lng),
              tags: const {'type': 'gas'},
              icon: await _stationBadgeIcon(
                label: '+${group.length}', brand: null,
                stationName: '주유소 ${group.length}곳', isCheapest: false,
              ),
            );
            marker.setOnTapListener((_) async {
              await _restoreMarkerIcon(_selectedStation, _lastMinGasPrice);
              _selectCluster(group.cast<dynamic>());
            });
            _markerRefs[markerId] = marker;
            return marker;
          }());
        }
      });
    }

    if (_showEv) {
      final evGroups = _groupByCluster<EvStation>(
        evStations, (s) => NLatLng(s.lat, s.lng),
      );
      evGroups.forEach((keyc, group) {
        if (group.length == 1) {
          final s = group.first;
          final isSelected = _selectedStation is EvStation &&
              (_selectedStation as EvStation).statId == s.statId;
          final markerLabel = s.isTesla ? 'Tesla' : '${s.availableCount}/${s.totalCount}';
          final markerId = 'ev_${s.statId}';
          markerFutures.add(() async {
            final marker = NClusterableMarker(
              id: markerId,
              position: NLatLng(s.lat, s.lng),
              tags: const {'type': 'ev'},
              icon: await _stationBadgeIcon(
                label: markerLabel, isEv: true, isHighlighted: isSelected,
              ),
            );
            marker.setOnTapListener((_) async {
              final prev = _selectedStation;
              if (prev is EvStation && prev.statId == s.statId) {
                await _dismissSheet();
                return;
              }
              await _restoreMarkerIcon(prev, _lastMinGasPrice);
              _selectStation(s);
              await _highlightMarker(markerId, markerLabel, isEv: true);
            });
            _markerRefs[markerId] = marker;
            return marker;
          }());
        } else {
          final first = group.first;
          final markerId = 'ev_cluster_$keyc';
          markerFutures.add(() async {
            final marker = NClusterableMarker(
              id: markerId,
              position: NLatLng(first.lat, first.lng),
              tags: const {'type': 'ev'},
              icon: await _stationBadgeIcon(
                label: '+${group.length}', isEv: true,
              ),
            );
            marker.setOnTapListener((_) async {
              await _restoreMarkerIcon(_selectedStation, _lastMinGasPrice);
              _selectCluster(group.cast<dynamic>());
            });
            _markerRefs[markerId] = marker;
            return marker;
          }());
        }
      });
    }

    if (gen != _markersGeneration) return;
    final markers = await Future.wait(markerFutures);
    if (gen != _markersGeneration) return;
    if (markers.isNotEmpty) {
      await controller.addOverlayAll(markers.toSet());
    }
  }

  /// 특정 마커를 강조(선택) 스타일로 변경.
  Future<void> _highlightMarker(String markerId, String label, {String? brand, String? stationName, bool isEv = false}) async {
    final marker = _markerRefs[markerId];
    if (marker == null) return;
    marker.setIcon(await _stationBadgeIcon(label: label, brand: brand, stationName: stationName, isEv: isEv, isHighlighted: true));
  }

  /// 이전에 선택된 스테이션 마커를 원래 아이콘으로 복원 (전체 redraw 없이).
  Future<void> _restoreMarkerIcon(dynamic prev, double? minGasPrice) async {
    if (prev == null) return;
    if (prev is GasStation) {
      final markerId = 'gas_${prev.id}';
      final marker = _markerRefs[markerId];
      if (marker == null) return;
      final isCheapest = minGasPrice != null && prev.price == minGasPrice;
      marker.setIcon(await _stationBadgeIcon(
        label: prev.priceText, brand: prev.brand, stationName: prev.name, isCheapest: isCheapest,
      ));
    } else if (prev is EvStation) {
      final markerId = 'ev_${prev.statId}';
      final marker = _markerRefs[markerId];
      if (marker == null) return;
      marker.setIcon(await _stationBadgeIcon(
        label: prev.isTesla ? 'Tesla' : '${prev.availableCount}/${prev.totalCount}',
        isEv: true,
      ));
    }
  }

  // ─── 클러스터 목록 시트 (같은 GPS 마커 N개) ───
  Widget _buildClusterListSheet(List<dynamic> stations, bool isDark) {
    final isEv = stations.first is EvStation;
    final accent = isEv ? AppColors.evGreen : AppColors.gasBlue;
    final kindLabel = isEv ? '충전소' : '주유소';

    // 호출처 가드는 있지만 build 중 _dismissSheet 호출되는 race 방어
    final sheetCtrl = _sheetController;
    if (sheetCtrl == null) return const SizedBox.shrink();

    return DraggableScrollableSheet(
      key: ValueKey('cluster_sheet_${stations.length}_${stations.hashCode}'),
      controller: sheetCtrl,
      initialChildSize: 0.55,
      minChildSize: 0.2,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.55, 0.95],
      builder: (ctx, scrollCtrl) {
        return Material(
          color: isDark ? AppColors.darkBg : Colors.white,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCardBorder : const Color(0xFFD0D5DA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.location_on_rounded, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Text('이 위치에 $kindLabel ${stations.length}곳',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    onPressed: _dismissSheet,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: stations.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1, thickness: 0.5,
                    color: isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE),
                    indent: 16, endIndent: 16,
                  ),
                  itemBuilder: (_, i) => _buildClusterItem(stations[i], isDark, accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClusterItem(dynamic s, bool isDark, Color accent) {
    String name;
    String address;
    String? subInfo;

    if (s is EvStation) {
      name = StationAliasService.resolveEv(s.statId, s.name);
      address = s.address;
      subInfo = '${s.availableCount}/${s.totalCount}대 사용 가능';
    } else if (s is GasStation) {
      name = StationAliasService.resolveGas(s.id, s.name);
      address = s.address;
      subInfo = s.priceText;
    } else {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () async {
        // 단일 상세 전환 + 카메라 이동 (살짝 줌인)
        final controller = _mapController;
        if (controller != null) {
          double lat;
          double lng;
          if (s is EvStation) { lat = s.lat; lng = s.lng; }
          else { lat = (s as GasStation).lat; lng = s.lng; }
          await controller.updateCamera(
            NCameraUpdate.scrollAndZoomTo(
              target: NLatLng(lat, lng),
              zoom: 16,
            )..setAnimation(animation: NCameraAnimation.easing, duration: const Duration(milliseconds: 280)),
          );
        }
        if (!mounted) return;
        _selectStation(s);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                s is EvStation ? Icons.ev_station_rounded : Icons.local_gas_station_rounded,
                size: 18, color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(address,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (subInfo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subInfo,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFAAAAAA)),
          ],
        ),
      ),
    );
  }

  // ─── 주유소 상세 DraggableScrollableSheet ───
  // 가격 행 1~4개 따라 높이가 달라지므로 보수적으로 넉넉하게 잡음
  static const double _gasHeroCardPx = 420.0;
  Widget _buildGasDetailSheet(GasStation s, bool isDark) {
    final sheetCtrl = _sheetController;
    if (sheetCtrl == null) return const SizedBox.shrink();
    final screenH = MediaQuery.of(context).size.height;
    final snap = (_gasHeroCardPx / screenH).clamp(0.38, 0.75);
    return DraggableScrollableSheet(
      key: ValueKey('gas_sheet_${s.id}'),
      controller: sheetCtrl,
      initialChildSize: snap,
      minChildSize: 0.2,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: [snap, 0.95],
      builder: (ctx, scrollCtrl) {
        return Material(
          color: isDark ? AppColors.darkBg : Colors.white,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: GasDetailContent(
            stationId: s.id,
            station: s,
            sheetController: scrollCtrl,
            sheetMode: true,
          ),
        );
      },
    );
  }

  // ─── EV 상세 DraggableScrollableSheet ───
  // 히어로 카드(드래그핸들 포함) 예상 픽셀 높이 → 화면 비율로 변환.
  // 폰 크기와 무관하게 "길 안내 시작" 버튼까지만 보이도록 동적 계산.
  static const double _evHeroCardPx = 360.0; // 드래그핸들+히어로+버튼 합산 픽셀
  Widget _buildEvDetailSheet(EvStation s, bool isDark) {
    final sheetCtrl = _sheetController;
    if (sheetCtrl == null) return const SizedBox.shrink();
    final screenH = MediaQuery.of(context).size.height;
    final snap = (_evHeroCardPx / screenH).clamp(0.35, 0.70);
    return DraggableScrollableSheet(
      key: ValueKey('ev_sheet_${s.statId}'),
      controller: sheetCtrl,
      initialChildSize: snap,
      minChildSize: 0.2,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: [snap, 0.95],
      builder: (ctx, scrollCtrl) {
        return Material(
          color: isDark ? AppColors.darkBg : Colors.white,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: EvDetailContent(
            station: s,
            sheetController: scrollCtrl,
            sheetMode: true,
            onSelectRoute: null,
          ),
        );
      },
    );
  }

  // ─── 이 지역 목록 시트 (지금 지도에 보이는 주유/충전소) ───
  // mapGas/EvStationsProvider 는 지도 영역·필터까지 이미 적용된 리스트.
  // 지도 이동 시 자동 재조회되므로 별도 '재검색' 버튼 없이 갱신됨.
  static const double _listPeek = 0.12;
  static const double _listMid = 0.45;
  static const double _listFull = 0.9;

  Widget _buildAreaListSheet(bool isDark, VehicleType vehicleType) {
    _ensureListSortDefault();
    final bg = isDark ? AppColors.darkMapOverlay : Colors.white;
    final handleColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFD0D5DA);

    // 어떤 종류를 보여줄지 — 기존 _showGas/_showEv 로직 그대로.
    final gasAsync = ref.watch(mapGasStationsProvider);
    final evAsync = ref.watch(mapEvStationsProvider);
    final showGasList = _showGas && vehicleType != VehicleType.ev;
    final showEvList = _showEv && vehicleType != VehicleType.gas;

    final loading = (showGasList && gasAsync.isLoading) ||
        (showEvList && evAsync.isLoading);

    // 표시 대상 합치기 (둘 다 켜진 both 모드면 가스+EV 함께).
    final gasList = showGasList ? (gasAsync.valueOrNull ?? const <GasStation>[]) : const <GasStation>[];
    final evList = showEvList ? (evAsync.valueOrNull ?? const <EvStation>[]) : const <EvStation>[];
    final items = <dynamic>[...gasList, ...evList];
    _sortAreaItems(items);
    final count = items.length;

    return DraggableScrollableSheet(
      controller: _listSheetController,
      initialChildSize: _listPeek,
      minChildSize: _listPeek,
      maxChildSize: _listFull,
      snap: true,
      snapSizes: const [_listPeek, _listMid, _listFull],
      builder: (ctx, scrollCtrl) {
        return Material(
          color: bg,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // drag handle — 시트 전체 영역에서 드래그 되도록 헤더는 ListView 밖.
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: handleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              _buildAreaListHeader(isDark, count, showGasList, showEvList),
              const SizedBox(height: 4),
              Divider(
                height: 1, thickness: 0.5,
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE),
              ),
              Expanded(
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : items.isEmpty
                        ? ListView(
                            // 빈 상태에서도 시트를 드래그할 수 있게 스크롤 가능 영역 유지.
                            controller: scrollCtrl,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 48),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_off_rounded,
                                          size: 32,
                                          color: isDark
                                              ? AppColors.darkTextMuted
                                              : AppColors.lightTextMuted),
                                      const SizedBox(height: 10),
                                      Text('이 지역에 표시할 곳이 없어요',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? AppColors.darkTextSecondary
                                                : AppColors.lightTextSecondary,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding: EdgeInsets.fromLTRB(
                                0, 6, 0,
                                MediaQuery.of(context).padding.bottom + 12),
                            itemCount: items.length,
                            itemBuilder: (_, i) => _buildAreaListCard(items[i]),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAreaListHeader(
      bool isDark, int count, bool showGasList, bool showEvList) {
    // 정렬 칩은 가스가 있을 때만 가격순이 의미 있음. EV 전용이면 회원/비회원 가격이
    // 카드 sortMode 에 따르므로 여기선 가격/거리 토글만 제공(공통).
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text('이 지역 $count곳',
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: primary,
              )),
          const Spacer(),
          _buildSortChip('가격순', _listSortByPrice, isDark, () {
            if (!_listSortByPrice) setState(() => _listSortByPrice = true);
          }),
          const SizedBox(width: 6),
          _buildSortChip('거리순', !_listSortByPrice, isDark, () {
            if (_listSortByPrice) setState(() => _listSortByPrice = false);
          }),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, bool active, bool isDark, VoidCallback onTap) {
    final activeColor = AppColors.gasBlue;
    final fg = active
        ? Colors.white
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? activeColor
              : (isDark ? AppColors.darkCard : const Color(0xFFF1F3F6)),
          borderRadius: BorderRadius.circular(16),
          border: active
              ? null
              : Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : const Color(0xFFE0E4EA),
                  width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: fg,
            )),
      ),
    );
  }

  /// 카드 탭 공통 흐름 — 마커 탭과 동일: 카메라 이동(중앙) + 마커 강조 + 상세 진입.
  /// 시트는 mid 로 살짝 내려 지도/마커가 보이게 함.
  Future<void> _onAreaListTap(dynamic s) async {
    // 시트를 중간 스냅으로 내려 지도+강조 마커가 보이도록.
    if (_listSheetController.isAttached &&
        _listSheetController.size > _listMid + 0.02) {
      _listSheetController.animateTo(
        _listMid,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    final controller = _mapController;
    final prev = _selectedStation;
    await _restoreMarkerIcon(prev, _lastMinGasPrice);
    if (controller != null) {
      final lat = s is GasStation ? s.lat : (s as EvStation).lat;
      final lng = s is GasStation ? s.lng : (s as EvStation).lng;
      _suppressCameraChange = true;
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(lat, lng),
          zoom: 16,
        )..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 300)),
      );
      Future.delayed(const Duration(milliseconds: 650),
          () => _suppressCameraChange = false);
    }
    if (!mounted) return;
    // 마커 강조 + 상세 시트 진입 (마커 탭 흐름 재사용).
    if (s is GasStation) {
      final markerId = 'gas_${s.id}';
      final displayName = StationAliasService.resolveGas(s.id, s.name);
      _selectStation(s);
      await _highlightMarker(markerId, s.priceText,
          brand: s.brand, stationName: displayName);
    } else if (s is EvStation) {
      final markerId = 'ev_${s.statId}';
      final label = s.isTesla ? 'Tesla' : '${s.availableCount}/${s.totalCount}';
      _selectStation(s);
      await _highlightMarker(markerId, label, isEv: true);
    }
  }

  Widget _buildAreaListCard(dynamic s) {
    if (s is GasStation) {
      return GasStationCard(
        key: ValueKey('arealist_gas_${s.id}'),
        station: s,
        onTap: () => _onAreaListTap(s),
      );
    }
    if (s is EvStation) {
      return EvStationCard(
        key: ValueKey('arealist_ev_${s.statId}'),
        station: s,
        onTap: () => _onAreaListTap(s),
      );
    }
    return const SizedBox.shrink();
  }

  /// 정렬 — 가격순/거리순. EV distance 는 nullable 이라 null 은 뒤로.
  void _sortAreaItems(List<dynamic> items) {
    int byPrice(dynamic a, dynamic b) {
      final pa = _itemPrice(a);
      final pb = _itemPrice(b);
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    }
    int byDist(dynamic a, dynamic b) {
      final da = _itemDistance(a);
      final db = _itemDistance(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }
    items.sort(_listSortByPrice ? byPrice : byDist);
  }

  num? _itemPrice(dynamic s) {
    if (s is GasStation) return s.price;
    if (s is EvStation) return s.unitPriceFast ?? s.unitPriceSlow;
    return null;
  }

  double? _itemDistance(dynamic s) {
    if (s is GasStation) return s.distance;
    if (s is EvStation) return s.distance;
    return null;
  }

}

/// 검색한 장소를 가리키는 핀 + 이름 알약. 스테이션 마커(파랑/초록)와 구분되되
/// 너무 튀지 않는 차분한 로즈 톤. 이름은 흰 알약 위 Flutter 폰트로 깔끔하게.
class _SearchPin extends StatelessWidget {
  final String name;
  final TextStyle nameStyle;
  final double pillWidth;
  final double canvasWidth;
  final double canvasHeight;
  const _SearchPin({
    required this.name,
    required this.nameStyle,
    required this.pillWidth,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  // 바이올렛 — 주유 파랑/충전 초록과 안 겹치면서 그 사이에 자연스레 어울리는 톤.
  static const Color _pin = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    // 캔버스 크기를 고정하고 콘텐츠를 하단 정렬 — 여유(+4)는 위쪽 투명으로 가고
    // 핀 끝이 캔버스 맨 아래(앵커 0.5,1.0)에 오게 해 좌표를 정확히 가리킴.
    return SizedBox(
      width: canvasWidth,
      height: canvasHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (name.isNotEmpty) ...[
          Container(
            width: pillWidth,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _pin.withValues(alpha: 0.55), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: nameStyle,
            ),
          ),
          const SizedBox(height: 3),
        ],
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              const Icon(Icons.location_on, size: 44, color: Colors.white),
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.location_on, size: 40, color: _pin),
              ),
              const Positioned(
                top: 11,
                child: CircleAvatar(radius: 4.5, backgroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ],
        ),
      ),
    );
  }
}


