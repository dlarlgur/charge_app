import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/location_service.dart';
import '../../providers/providers.dart';
import '../detail/ev_detail_screen.dart';
import '../detail/gas_detail_screen.dart';
import '../filter/ev_filter_sheet.dart';
import '../filter/gas_filter_sheet.dart';
import '../widgets/gas_station_map_badge.dart';

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
  bool _showSearchHere = false;
  bool _mapReady = false;
  int _markersGeneration = 0;
  final Map<String, NMarker> _markerRefs = {};
  Timer? _markerDebounce;
  double? _lastMinGasPrice;
  bool _isLocating = false;
  bool _isAtMyLocation = false;
  bool _suppressCameraChange = false;
  DraggableScrollableController? _sheetController;

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
    _searchController.dispose();
    _sheetController?.dispose();
    super.dispose();
  }

  void _selectStation(dynamic station) {
    _sheetController?.dispose();
    _sheetController = DraggableScrollableController();
    mapSheetOpen.value = true;
    setState(() => _selectedStation = station);
  }

  Future<void> _dismissSheet() async {
    final prev = _selectedStation;
    mapSheetOpen.value = false;
    setState(() => _selectedStation = null);
    _sheetController?.dispose();
    _sheetController = null;
    await _restoreMarkerIcon(prev, _lastMinGasPrice);
  }

  void _scheduleUpdateMarkers() {
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 80), _updateMarkers);
  }

  void _clearMarkers() {
    _markerDebounce?.cancel();
    _markersGeneration++;
    _markerRefs.clear();
    _mapController?.clearOverlays(type: NOverlayType.marker);
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
    final radius = bounds != null
        ? _boundsToRadius(bounds, pos.target)
        : _zoomToRadius(pos.zoom);
    ref.read(mapCenterProvider.notifier).state = (lat: pos.target.latitude, lng: pos.target.longitude);
    ref.read(mapRadiusProvider.notifier).state = radius;
    if (_selectedStation != null) await _dismissSheet();
    setState(() { _showSearchHere = false; });
  }

  // ─── 검색 ───
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearchLoading = true);
    try {
      final center = ref.read(mapCenterProvider);
      final results = await ApiService().searchPlaces(
        query.trim(),
        lat: center?.lat,
        lng: center?.lng,
      );
      if (mounted) setState(() { _searchResults = results; _isSearchLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _searchResults = []; _isSearchLoading = false; });
    }
  }

  void _moveToPlace(Map<String, dynamic> place) {
    _saveToHistory(place);
    final lat = (place['lat'] as num).toDouble();
    final lng = (place['lng'] as num).toDouble();
    _mapController?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(lat, lng),
      zoom: 14,
    ));
    ref.read(mapCenterProvider.notifier).state = (lat: lat, lng: lng);
    setState(() {
      _isSearchMode = false;
      _searchResults = [];
      _showSearchHere = false;
    });
    _searchController.clear();
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
                decoration: BoxDecoration(color: AppColors.gasBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.local_gas_station_rounded, color: AppColors.gasBlue, size: 20),
              ),
              title: const Text('주유소 필터'),
              onTap: () { Navigator.pop(context); GasFilterSheet.show(context); },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.evGreen.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
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

    return Scaffold(
      body: Stack(
        children: [
          // ─── 네이버 지도 ───
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: const NCameraPosition(
                target: NLatLng(37.5665, 126.9780),
                zoom: 14,
              ),
              nightModeEnable: isDark,
              locationButtonEnable: false,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) {
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
              _updateMarkers();
            },
            onCameraChange: (_, __) {
              if (_suppressCameraChange) return;
              if (_mapReady && !_isSearchMode) {
                setState(() {
                  _showSearchHere = true;
                  _isAtMyLocation = false;
                });
              }
            },
            onMapTapped: (_, __) {
              if (_isSearchMode) {
                setState(() { _isSearchMode = false; _searchResults = []; _searchController.clear(); });
              } else if (_selectedStation != null) {
                _dismissSheet();
              }
            },
          ),

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
            bottom: MediaQuery.of(context).padding.bottom + (_selectedStation != null ? 200 : 24),
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
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

          // ─── 하단 상세 시트 ───
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
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
                      onChanged: _performSearch,
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 6, offset: const Offset(0, 2))],
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 6, offset: const Offset(0, 2))],
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10)],
          border: Border.all(color: AppColors.gasBlue.withOpacity(0.4)),
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

  // ─── 마커 배지 아이콘 (로고 + 가격/텍스트 카드 스타일) ───
  Future<NOverlayImage> _stationBadgeIcon({
    required String label,
    String? brand,
    String? stationName,
    bool isEv = false,
    bool isHighlighted = false,
    bool isCheapest = false,
  }) {
    final Color borderColor = isHighlighted
        ? _kSelectedColor
        : (isCheapest ? const Color(0xFFEF4444) : const Color(0xFFDDDDDD));
    final Color textColor = isHighlighted
        ? _kSelectedColor
        : (isCheapest ? const Color(0xFFEF4444) : const Color(0xFF1a1a1a));
    return GasStationMapBadge.overlayImage(
      context,
      label: label,
      brand: brand,
      stationName: stationName,
      isEv: isEv,
      borderColor: borderColor,
      textColor: textColor,
      emphasizeBorder: isHighlighted,
    );
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

    final gen = ++_markersGeneration;
    _markerRefs.clear();
    await controller.clearOverlays(type: NOverlayType.marker);
    if (gen != _markersGeneration) return;

    final gasStations = _spreadSample(ref.read(mapGasStationsProvider).valueOrNull ?? [], 150);
    final evStations = _spreadSample(ref.read(mapEvStationsProvider).valueOrNull ?? [], 150);

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

    if (_showGas) {
      for (final s in gasStations) {
        if (gen != _markersGeneration) return;
        final isCheapest = minGasPrice != null && s.price == minGasPrice;
        final isSelected = _selectedStation != null &&
            _selectedStation is GasStation &&
            (_selectedStation as GasStation).id == s.id;
        final label = s.priceText;
        final markerId = 'gas_${s.id}';
        final marker = NMarker(
          id: markerId,
          position: NLatLng(s.lat, s.lng),
          icon: await _stationBadgeIcon(
            label: label, brand: s.brand, stationName: s.name,
            isHighlighted: isSelected, isCheapest: isCheapest,
          ),
        );
        _markerRefs[markerId] = marker;
        marker.setOnTapListener((_) async {
          final prev = _selectedStation;
          if (prev is GasStation && prev.id == s.id) {
            await _dismissSheet();
            return;
          }
          await _restoreMarkerIcon(prev, _lastMinGasPrice);
          _selectStation(s);
          await _highlightMarker(markerId, label, brand: s.brand, stationName: s.name);
        });
        await controller.addOverlay(marker);
      }
    }

    if (_showEv) {
      for (final s in evStations) {
        if (gen != _markersGeneration) return;
        final isSelected = _selectedStation != null &&
            _selectedStation is EvStation &&
            (_selectedStation as EvStation).statId == s.statId;
        final markerLabel = s.isTesla ? 'Tesla' : '${s.availableCount}/${s.totalCount}';
        final markerId = 'ev_${s.statId}';
        final marker = NMarker(
          id: markerId,
          position: NLatLng(s.lat, s.lng),
          icon: await _stationBadgeIcon(
            label: markerLabel, isEv: true, isHighlighted: isSelected,
          ),
        );
        _markerRefs[markerId] = marker;
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
        await controller.addOverlay(marker);
      }
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

  void _openNavigation(double lat, double lng, String name) {
    showNavigationSheet(context, lat: lat, lng: lng, name: name);
  }

  // ─── 주유소 상세 DraggableScrollableSheet ───
  // 가격 행 1~4개 따라 높이가 달라지므로 보수적으로 넉넉하게 잡음
  static const double _gasHeroCardPx = 420.0;
  Widget _buildGasDetailSheet(GasStation s, bool isDark) {
    final screenH = MediaQuery.of(context).size.height;
    final snap = (_gasHeroCardPx / screenH).clamp(0.38, 0.75);
    return DraggableScrollableSheet(
      key: ValueKey('gas_sheet_${s.id}'),
      controller: _sheetController!,
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
    final screenH = MediaQuery.of(context).size.height;
    final snap = (_evHeroCardPx / screenH).clamp(0.35, 0.70);
    return DraggableScrollableSheet(
      key: ValueKey('ev_sheet_${s.statId}'),
      controller: _sheetController!,
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

}


