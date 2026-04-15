import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../core/navigation/app_route_observer.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/models/models.dart';
import '../../data/services/alert_service.dart';
import '../../data/services/api_service.dart';
import '../../data/services/watch_service.dart';
import '../../data/services/location_service.dart';
import '../../providers/providers.dart';
import 'ai_onboarding_screen.dart';
import 'ai_result_screen.dart';
import 'ai_vehicle_list_screen.dart';
import 'ev_result_screen.dart';
import '../widgets/gas_station_map_badge.dart';
import '../detail/ev_detail_screen.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kDanger = Color(0xFFE24B4A);

// 사용자 선택 모드(A/B) 색상
const _kCompareBlue = Color(0xFF1D6FE0);

class AiMainScreen extends ConsumerStatefulWidget {
  const AiMainScreen({super.key});

  @override
  ConsumerState<AiMainScreen> createState() => _AiMainScreenState();
}

class _AiMainScreenState extends ConsumerState<AiMainScreen> with RouteAware {
  // ── 지도 ──
  NaverMapController? _mapController;
  bool _brandImagesCached = false;
  StreamSubscription<({double lat, double lng})>? _locationSub;
  bool _isLocating = false;
  bool _isAtMyLocation = false;
  bool _suppressCameraChange = false;
  bool _addressLoaded = false;

  // ── 피커 모드 (지도에서 위치 선택) ──
  bool _isPickerMode = false;
  bool _pickingOrigin = false;
  String? _pickerAddress;
  bool _isReverseGeocoding = false;
  NLatLng? _pickerLatLng;
  Timer? _reverseGeocodeDebounce;

  // ── 현재 GPS 역지오코딩 주소 ──
  String? _currentLocationAddress;

  // ── 출발지 / 목적지 ──
  double? _originLat, _originLng;
  String? _originName;
  double? _destLat, _destLng;
  String? _destName;

  // ── 분석에 사용된 마지막 경로 (결과화면 지도용) ──
  double _lastStartLat = 0, _lastStartLng = 0;
  List<Map<String, dynamic>> _lastPathPoints = [];
  List<Map<String, dynamic>>? _lastPathSegments; // 교통 색상용

  // ── 잔량/목표 ──
  double _currentLevelPercent = 25.0;
  String _targetMode = 'FULL';
  final _priceController = TextEditingController(text: '50000');
  final _literController = TextEditingController(text: '20');

  // ── 분석 상태 ──
  bool _aiAnalyzing = false;    // AI 분석 탭 로딩
  bool _userSelecting = false;  // 사용자 선택 탭 로딩
  String _userSelectingMessage = '불러오는 중...';
  bool _isSelectSheetVisible = false;
  final DraggableScrollableController _selectSheetCtrl = DraggableScrollableController();
  String? _errorMessage;
  bool _onboardingPushed = false;

  // ── 결과 지도 모드 ──
  bool _isResultMode = false;
  Map<String, dynamic>? _lastResultData;
  String? _lastRouteSummary;

  // ── 사용자 선택 모드 ──
  bool _isSelectMode = false;
  List<Map<String, dynamic>>? _selectableStations;
  bool _highwayFilterActive = false;
  String? _selectedStationAId;
  String? _selectedStationBId;
  bool _isCompareResultMode = false;
  bool _isEvResultMode = false;
  bool _isEvSelectMode = false;
  List<Map<String, dynamic>> _evSelectCandidates = [];
  // 직접선택 경로 보기 후 백버튼 복원용
  List<Map<String, dynamic>> _prevEvSelectCandidates = [];
  // EV 결과 화면에서 "지도에서 경로 보기" 중인지 (백버튼으로 결과 복원용)
  bool _isEvResultMapView = false;
  String _aiAnalysisType = 'gas'; // gas | ev
  String _evChargerType = 'FAST'; // FAST | SLOW
  bool _evHighwayOnly = false;   // 고속도로 충전소만

  // ── 검색 기록 ──
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _searchHistoryItems = [];

  // ── 마지막으로 동기화된 차량 ID (차량 전환 감지용) ──
  String? _lastSyncedVehicleId;

  // ── 결과 패널 시트 크기 추적 ──
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _sheetSize = 0.45;
  DateTime? _lastInScreenBackHandledAt;
  /// `DraggableScrollableSheet` 빌더가 넘기는 스크롤 컨트롤러 (결과·비교 본문)
  ScrollController? _resultSheetScrollController;
  PageRoute<void>? _routeAwarePageRoute;

  /// 시트 확대 드래그가 먹히려면 본문 스크롤이 맨 위(0)여야 한다.
  void _resetResultSheetScrollToTop() {
    final c = _resultSheetScrollController;
    if (c == null || !c.hasClients) return;
    if (c.positions.length != 1) return;
    if (c.offset <= 0) return;
    c.jumpTo(0);
  }

  /// 지도 포커스용으로 시트를 최소 높이까지 내린다.
  /// 맨 위로 스크롤을 점프시키는 건 시트가 내려간 **뒤**에만 한다. (먼저 점프하면 DraggableScrollableSheet와
  /// 본문 스크롤이 꼬여, '지도에서 경로 보기' 후 살짝 올리면 리스트만 보이는 것처럼 느껴질 수 있음)
  Future<void> _collapseResultSheetForMapFocus() async {
    if (!_sheetController.isAttached) return;
    const targetSize = 0.12;
    if ((_sheetController.size - targetSize).abs() < 0.01) {
      if (mounted) _resetResultSheetScrollToTop();
      return;
    }
    try {
      await _sheetController.animateTo(
        targetSize,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
    if (mounted) _resetResultSheetScrollToTop();
  }

  // ── AI 추천 복원용 원본 파라미터 ──
  List<Map<String, dynamic>> _lastRecPathPoints = [];
  List<Map<String, dynamic>>? _lastRecSegments;
  double? _lastRecStLat, _lastRecStLng;
  String _lastRecStName = '';
  int? _lastRecStPrice;
  double? _lastRecSt2Lat, _lastRecSt2Lng;
  String _lastRecSt2Name = '';
  int? _lastRecSt2Price;
  String? _lastRecStBrand;
  String? _lastRecSt2Brand;
  List<dynamic>? _lastRecAlternatives;

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _sheetController.addListener(_onSheetChanged);
  }

  void _onSheetChanged() {
    if (!mounted || !_sheetController.isAttached) return;
    final s = _sheetController.size;
    // 최소 높이에 붙어 있을 때 스크롤이 남아 있으면, 위로 드래그해도 시트만 안 커지고 본문만 스크롤된다.
    if (s <= 0.125) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetResultSheetScrollToTop();
      });
    }
    setState(() => _sheetSize = s);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_addressLoaded) {
      _addressLoaded = true;
      _loadCurrentAddress();
    }
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _routeAwarePageRoute) {
      if (_routeAwarePageRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _routeAwarePageRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    // 상세 등에서 pop 후 시트가 접힌 상태면 스크롤이 남아 확대 드래그가 안 먹을 수 있음
    if (_sheetController.isAttached && _sheetController.size <= 0.125) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetResultSheetScrollToTop();
      });
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    _selectSheetCtrl.dispose();
    _priceController.dispose();
    _literController.dispose();
    _reverseGeocodeDebounce?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  // 선택된 차량 프로필 읽기
  VehicleProfile? _readSelectedVehicle(Box box) {
    final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    final rawVehicles = box.get(AppConstants.keyAiVehicles);
    if (rawVehicles == null) return null;
    try {
      final List decoded = jsonDecode(rawVehicles as String);
      final all = decoded.map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>)).toList();
      return all.cast<VehicleProfile?>().firstWhere(
        (v) => v?.id == selectedId, orElse: () => all.isNotEmpty ? all.first : null);
    } catch (_) { return null; }
  }

  // 차량 프로필 currentLevelPercent / targetMode / targetValue 저장
  void _saveVehicleLevel(Box box, {required double level, required String mode, double? price}) {
    final rawVehicles = box.get(AppConstants.keyAiVehicles);
    final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    if (rawVehicles == null || selectedId == null) return;
    try {
      final List decoded = jsonDecode(rawVehicles as String);
      final all = decoded.map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>)).toList();
      final idx = all.indexWhere((v) => v.id == selectedId);
      if (idx < 0) return;
      all[idx] = all[idx].copyWith(
        currentLevelPercent: level,
        targetMode: mode,
        targetValue: price ?? all[idx].targetValue,
      );
      box.put(AppConstants.keyAiVehicles, jsonEncode(all.map((v) => v.toJson()).toList()));
    } catch (_) {}
  }

  void _loadSaved() {
    final box = Hive.box(AppConstants.settingsBox);

    // 선택된 차량 프로필 기준으로 로드
    final vehicle = _readSelectedVehicle(box);
    if (vehicle != null) {
      _currentLevelPercent = vehicle.currentLevelPercent;
      _targetMode = vehicle.targetMode;
      _priceController.text = vehicle.targetValue.toStringAsFixed(0);
      final liter = vehicle.targetValue; // 리터 모드일 때도 targetValue 사용
      _literController.text = liter == liter.roundToDouble()
          ? liter.toStringAsFixed(0)
          : liter.toStringAsFixed(1);
    } else {
      // 차량 없을 때 글로벌 fallback
      _currentLevelPercent =
          (box.get(AppConstants.keyAiCurrentLevelPercent, defaultValue: 25.0) as num).toDouble();
      _targetMode = box.get(AppConstants.keyAiTargetMode, defaultValue: 'FULL') as String;
      final price = (box.get(AppConstants.keyAiTargetValue, defaultValue: 50000.0) as num).toDouble();
      _priceController.text = price.toStringAsFixed(0);
      final liter = (box.get(AppConstants.keyAiLiterTarget, defaultValue: 20.0) as num).toDouble();
      _literController.text = liter == liter.roundToDouble()
          ? liter.toStringAsFixed(0)
          : liter.toStringAsFixed(1);
    }
    
    // 검색 기록: 지도 탭과 동일 키 — Hive에는 List<String> (각 요소는 jsonEncode(장소 Map)) 로 저장됨
    _searchHistoryItems = _readSearchHistoryItems(box);
    _searchHistory = _searchHistoryItems
        .map((e) => e['name']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// `keySearchHistory` 값이 List(지도탭) / String(구 AI JSON 배열) 어느 쪽이든
  /// {name, lat, lng} 형태의 목록으로 정규화
  List<Map<String, dynamic>> _readSearchHistoryItems(Box box) {
    final raw = box.get(AppConstants.keySearchHistory);
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! String || e.isEmpty) continue;
        try {
          final m = jsonDecode(e);
          if (m is Map) {
            final n = m['name']?.toString();
            if (n != null && n.isNotEmpty) {
              items.add({
                'name': n,
                'lat': m['lat'],
                'lng': m['lng'],
                'address': m['address'],
              });
            }
          } else {
            items.add({'name': e});
          }
        } catch (_) {
          items.add({'name': e});
        }
      }
      return items;
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty) {
              items.add({'name': item});
            } else if (item is Map) {
              final n = item['name']?.toString();
              if (n != null && n.isNotEmpty) {
                items.add({
                  'name': n,
                  'lat': item['lat'],
                  'lng': item['lng'],
                  'address': item['address'],
                });
              }
            }
          }
        }
      } catch (_) {}
    }
    return items;
  }

  Future<void> _loadCurrentAddress() async {
    try {
      final baseLoc = await ref.read(locationProvider.future);
      final loc = baseLoc ??
          await LocationService().getFreshPosition().then(
                (p) => p == null ? null : (lat: p.latitude, lng: p.longitude),
              );
      if (loc == null || !mounted) return;
      final addr = await ApiService().reverseGeocode(loc.lat, loc.lng);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _currentLocationAddress = addr);
      }
    } catch (_) {}
  }

  /// 지도 탭과 동일 형식: `List<String>` 에 각 `jsonEncode({name, lat, lng})` 저장
  void _saveSearchHistory(String name, {double? lat, double? lng}) {
    if (name.isEmpty) return;

    final box = Hive.box(AppConstants.settingsBox);
    var rows = <String>[];
    final raw = box.get(AppConstants.keySearchHistory);
    if (raw is List) {
      rows = raw.whereType<String>().toList();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) {
          rows = d.map((e) => e is String ? e : jsonEncode(e)).toList();
        }
      } catch (_) {}
    }

    rows.removeWhere((s) {
      try {
        final m = jsonDecode(s);
        if (m is Map) return m['name']?.toString() == name;
      } catch (_) {}
      return false;
    });

    rows.insert(0, jsonEncode({'name': name, 'lat': lat, 'lng': lng}));
    if (rows.length > 15) rows = rows.sublist(0, 15);

    box.put(AppConstants.keySearchHistory, rows);

    if (mounted) {
      setState(() {
        _searchHistoryItems = _readSearchHistoryItems(box);
        _searchHistory = _searchHistoryItems
            .map((e) => e['name']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      });
    } else {
      _searchHistoryItems = _readSearchHistoryItems(box);
      _searchHistory = _searchHistoryItems
          .map((e) => e['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }

  // ── 지도 준비 → GPS 위치로 이동 + location overlay 표시 (지도탭과 동일) ──
  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    GasStationMapBadge.precacheBrandImages(context).then((_) {
      _brandImagesCached = true;
    });
    ref.read(locationProvider.future).then((loc) {
      if (loc == null || !mounted) return;
      _suppressCameraChange = true;
      controller.updateCamera(NCameraUpdate.withParams(
        target: NLatLng(loc.lat, loc.lng),
        zoom: 14,
      ));
      final overlay = controller.getLocationOverlay();
      overlay.setIsVisible(true);
      overlay.setPosition(NLatLng(loc.lat, loc.lng));
      if (mounted) setState(() => _isAtMyLocation = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        _suppressCameraChange = false;
      });
    });

    // 위치 스트림 구독 → overlay 실시간 갱신
    _locationSub?.cancel();
    _locationSub = ref.read(locationStreamProvider.stream).listen((loc) {
      final overlay = _mapController?.getLocationOverlay();
      overlay?.setIsVisible(true);
      overlay?.setPosition(NLatLng(loc.lat, loc.lng));
    });
  }

  // ── 현재 위치 버튼 ──
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
      if (mounted) setState(() => _isAtMyLocation = true);
      final addr = await ApiService().reverseGeocode(loc.lat, loc.lng);
      if (mounted && addr != null && addr.isNotEmpty) {
        setState(() => _currentLocationAddress = addr);
      }
      Future.delayed(const Duration(milliseconds: 800), () {
        _suppressCameraChange = false;
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ── 카메라 정지 → 피커 모드에서 역지오코딩 ──
  void _onCameraIdle() async {
    if (!_isPickerMode || _mapController == null || _suppressCameraChange) return;
    final NCameraPosition pos;
    try {
      pos = await _mapController!.getCameraPosition();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickerLatLng = pos.target;
      _isReverseGeocoding = true;
    });
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 400), () async {
      final addr = await ApiService().reverseGeocode(
        pos.target.latitude, pos.target.longitude);
      if (mounted) {
        setState(() {
          _pickerAddress = addr ?? '주소를 가져올 수 없습니다';
          _isReverseGeocoding = false;
        });
      }
    });
  }

  void _enterPickerMode({required bool isOrigin}) {
    setState(() {
      _isPickerMode = true;
      _pickingOrigin = isOrigin;
      _pickerAddress = null;
      _pickerLatLng = null;
      _isReverseGeocoding = true;
    });
    // _suppressCameraChange(800ms)가 풀린 뒤에 역지오코딩 시작
    Future.delayed(const Duration(milliseconds: 900), _onCameraIdle);
  }

  void _exitPickerMode() {
    setState(() {
      _isPickerMode = false;
      _pickerAddress = null;
      _pickerLatLng = null;
      _isReverseGeocoding = false;
    });
  }

  void _confirmMapPick() {
    if (_pickerLatLng == null) return;
    final lat = _pickerLatLng!.latitude;
    final lng = _pickerLatLng!.longitude;
    final name = _pickerAddress ?? '선택한 위치';
    if (_pickingOrigin) {
      setState(() { _originLat = lat; _originLng = lng; _originName = name; });
      if (_destLat != null && _destLng != null) {
        unawaited(_showQuickRoutePreview());
      }
    } else {
      setState(() { _destLat = lat; _destLng = lng; _destName = name; });
      unawaited(_showQuickRoutePreview());
    }
    _exitPickerMode();
  }

  // ── 위치 선택 시트 ──
  void _showLocationSheet({required bool isOrigin}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LocationPickerSheet(
        isOrigin: isOrigin,
        currentLocationAddress: _currentLocationAddress,
        searchHistory: _searchHistory,
        searchHistoryItems: _searchHistoryItems,
        onMyLocation: () {
          Navigator.pop(ctx);
          if (isOrigin) {
            setState(() { _originLat = null; _originLng = null; _originName = null; });
            unawaited(_loadCurrentAddress());
          } else {
            ref.read(locationProvider.future).then((baseLoc) async {
              final loc = baseLoc ??
                  await LocationService().getFreshPosition().then(
                        (p) => p == null ? null : (lat: p.latitude, lng: p.longitude),
                      );
              if (loc == null || !mounted) return;
              final resolved = await ApiService().reverseGeocode(loc.lat, loc.lng);
              final address = (resolved != null && resolved.isNotEmpty)
                  ? resolved
                  : (_currentLocationAddress ?? '현재 위치');
              setState(() {
                _destLat = loc.lat;
                _destLng = loc.lng;
                _destName = address;
                if (resolved != null && resolved.isNotEmpty) {
                  _currentLocationAddress = resolved;
                }
              });
              unawaited(_showQuickRoutePreview());
            });
          }
        },
        onMapPick: () {
          Navigator.pop(ctx);
          _enterPickerMode(isOrigin: isOrigin);
        },
        onSearchResult: (r) {
          Navigator.pop(ctx);
          final lat = _asDouble(r['lat']);
          final lng = _asDouble(r['lng']);
          final name = r['name']?.toString() ?? '';

          _saveSearchHistory(name, lat: lat, lng: lng);
          
          if (isOrigin) {
            setState(() { _originLat = lat; _originLng = lng; _originName = name; });
            if (_destLat != null && _destLng != null) {
              unawaited(_showQuickRoutePreview());
            }
          } else {
            setState(() { _destLat = lat; _destLng = lng; _destName = name; _errorMessage = null; });
            unawaited(_showQuickRoutePreview());
          }
        },
      ),
    );
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<({double lat, double lng})?> _resolveCurrentLocationForStart() async {
    // 1) provider 결과
    final loc = await ref.read(locationProvider.future);
    if (loc != null) return loc;
    // 2) stream 최신값
    final streamed = ref.read(locationStreamProvider).valueOrNull;
    if (streamed != null) return streamed;
    // 3) 서비스의 강제 갱신
    final fresh = await LocationService().getFreshPosition();
    if (fresh != null) return (lat: fresh.latitude, lng: fresh.longitude);
    return null;
  }

  Future<void> _showQuickRoutePreview() async {
    if (_mapController == null || _destLat == null || _destLng == null) return;

    double startLat;
    double startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final baseLoc = await ref.read(locationProvider.future);
      final loc = baseLoc ??
          await LocationService().getFreshPosition().then(
                (p) => p == null ? null : (lat: p.latitude, lng: p.longitude),
              );
      if (loc == null || !mounted) return;
      startLat = loc.lat;
      startLng = loc.lng;
    }

    var pathPoints = <Map<String, dynamic>>[
      {'lat': startLat, 'lng': startLng},
      {'lat': _destLat!, 'lng': _destLng!},
    ];
    List<Map<String, dynamic>>? pathSegments;
    try {
      final dr = await ApiService().getDrivingRoute(
        startLat: startLat,
        startLng: startLng,
        goalLat: _destLat!,
        goalLng: _destLng!,
      );
      if (dr['success'] == true) {
        final parsed = _pathPointsFromServerJson(dr['path_points']);
        if (parsed != null) pathPoints = parsed;
        pathSegments = _parsePathSegments(dr['path_segments']);
      }
    } catch (_) {}

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;
    _lastPathSegments = pathSegments;

    _drawResultOnMap(
      pathPoints: pathPoints,
      pathSegments: pathSegments,
      originLat: startLat,
      originLng: startLng,
      stLat: null,
      stLng: null,
      stName: '',
      destLat: _destLat!,
      destLng: _destLng!,
    );
  }

  // ── 분석 실행 ──
  Future<void> _runAnalyze() async {
    final box = Hive.box(AppConstants.settingsBox);
    final fuelCode =
        box.get(AppConstants.keyAiFuelType, defaultValue: FuelType.gasoline.code) as String;
    final tankCapacity =
        (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num).toDouble();
    final efficiency =
        (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num).toDouble();

    if (_destLat == null || _destLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지를 선택해 주세요.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_targetMode == 'PRICE') {
      final p = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
      if (p <= 0) { setState(() => _errorMessage = '목표 금액을 올바르게 입력해주세요.'); return; }
    }
    if (_targetMode == 'LITER') {
      final l = double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0;
      if (l <= 0) { setState(() => _errorMessage = '목표 리터를 올바르게 입력해주세요.'); return; }
    }

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      startLat = loc.lat;
      startLng = loc.lng;
    }

    final priceTarget = _targetMode == 'PRICE'
        ? (double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    final literTarget = _targetMode == 'LITER'
        ? (double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    final apiTargetValue = _targetMode == 'PRICE' ? priceTarget
        : (_targetMode == 'LITER' ? literTarget : 0.0);

    _saveVehicleLevel(box, level: _currentLevelPercent, mode: _targetMode,
        price: _targetMode == 'PRICE' ? priceTarget : (_targetMode == 'LITER' ? literTarget : null));
    // 글로벌 fallback
    box.put(AppConstants.keyAiCurrentLevelPercent, _currentLevelPercent);
    box.put(AppConstants.keyAiTargetMode, _targetMode);
    if (_targetMode == 'PRICE') box.put(AppConstants.keyAiTargetValue, priceTarget);
    if (_targetMode == 'LITER') box.put(AppConstants.keyAiLiterTarget, literTarget);

    setState(() { _aiAnalyzing = true; _errorMessage = null; });

    var pathPoints = <Map<String, dynamic>>[
      {'lat': startLat, 'lng': startLng},
      {'lat': _destLat!, 'lng': _destLng!},
    ];
    int? directDurationMs;

    try {
      final dr = await ApiService().getDrivingRoute(
        startLat: startLat, startLng: startLng,
        goalLat: _destLat!, goalLng: _destLng!,
      );
      if (dr['success'] == true) {
        // 직접 경로 소요시간 (고속도로 IC 필터용)
        if (dr['duration_ms'] is num) {
          directDurationMs = (dr['duration_ms'] as num).round();
        }
        final raw = dr['path_points'];
        if (raw is List && raw.length >= 2) {
          final parsed = <Map<String, dynamic>>[];
          for (final e in raw) {
            if (e is Map) {
              final lat = e['lat']; final lng = e['lng'];
              if (lat is num && lng is num) {
                parsed.add({'lat': lat.toDouble(), 'lng': lng.toDouble()});
              }
            }
          }
          if (parsed.length >= 2) pathPoints = parsed;
        }
      }
    } catch (_) {}

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;

    final requestId = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999999)}';
    final body = <String, dynamic>{
      'request_id': requestId,
      'vehicle_info': {
        'fuel_type': fuelCode,
        'tank_capacity_l': tankCapacity,
        'efficiency_km_per_l': efficiency,
      },
      'current_status': {
        'current_level_percent': _currentLevelPercent,
        'target_mode': _targetMode,
        'target_value': apiTargetValue,
      },
      'route_context': {
        'origin': {'lat': startLat, 'lng': startLng},
        'destination': {'lat': _destLat, 'lng': _destLng},
        'path_points': pathPoints,
        if (directDurationMs != null) 'duration_ms': directDurationMs,
      },
      'recommendation': {'top_n_candidates_returned': 3},
    };

    try {
      Map<String, dynamic> data;
      try {
        data = await ApiService().postRefuelAnalyze(body);
      } on DioException catch (e) {
        final raw = e.response?.data;
        String msg = '';
        if (raw is Map) {
          final err = raw['error'];
          if (err is Map && err['message'] != null) msg = err['message'].toString();
        }
        final isPrimaryInitError = msg.toLowerCase().contains('primary station') &&
            msg.toLowerCase().contains('before initialization');
        if (!isPrimaryInitError) rethrow;

        // 서버 특정 케이스 회피: recommendation 필드를 제거해 1회 재시도
        final retryBody = Map<String, dynamic>.from(body)..remove('recommendation');
        data = await ApiService().postRefuelAnalyze(retryBody);
      }
      if (!mounted) return;
      final status = data['meta'] is Map ? (data['meta'] as Map)['status']?.toString() : null;
      if (status == 'ok') {
        final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';
        final rec = data['recommendation'] is Map ? data['recommendation'] as Map<String, dynamic> : null;
        final choice = rec?['choice']?.toString() ?? 'on_route';
        final onRoute = data['on_route'] is Map ? data['on_route'] as Map<String, dynamic> : null;
        final bestDetour = data['best_detour'] is Map ? data['best_detour'] as Map<String, dynamic> : null;
        final onRouteSt = onRoute?['station'] is Map ? onRoute!['station'] as Map<String, dynamic> : null;
        final detourSt = bestDetour?['station'] is Map ? bestDetour!['station'] as Map<String, dynamic> : null;

        // 지도 표시는 타입 기준으로 고정:
        // - 경로상 최저가(on_route) = 파랑
        // - 우회 최저가(best_detour) = 주황
        // 추천 여부는 색이 아니라 라벨(배지)로만 표시
        final isRecDetour = choice == 'best_detour';

        double? stLat, stLng, st2Lat, st2Lng;
        String stName = '우회 최저가', st2Name = '경로상 최저가';
        int? stPrice, st2Price;

        // st = 우회 최저가 (분석 UI·지도 모두 파랑 #1D6FE0)
        if (detourSt != null) {
          stLat = detourSt['lat'] is num ? (detourSt['lat'] as num).toDouble() : null;
          stLng = detourSt['lng'] is num ? (detourSt['lng'] as num).toDouble() : null;
          final rawName = detourSt['name']?.toString() ?? '우회 최저가';
          stName = isRecDetour ? '추천 · $rawName' : rawName;
          final p = detourSt['price_won_per_liter'];
          stPrice = p is num ? p.round() : null;
        }

        // st2 = 경로상 최저가 (분석 UI·지도 모두 주황 #E8700A)
        if (onRouteSt != null) {
          st2Lat = onRouteSt['lat'] is num ? (onRouteSt['lat'] as num).toDouble() : null;
          st2Lng = onRouteSt['lng'] is num ? (onRouteSt['lng'] as num).toDouble() : null;
          final rawName = onRouteSt['name']?.toString() ?? '경로상 최저가';
          st2Name = !isRecDetour ? '추천 · $rawName' : rawName;
          final p2 = onRouteSt['price_won_per_liter'];
          st2Price = p2 is num ? p2.round() : null;
        }

        setState(() {
          _isResultMode = true;
          _lastResultData = data;
          _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
        });

        // 추천 주유소 경유 경로: 서버에서 미리 받은 전체 길찾기 우선, 없으면 클라이언트 네이버 호출
        var viaPathPoints = _lastPathPoints;
        List<Map<String, dynamic>>? viaSegments;
        final nav = data['navigation'] is Map ? data['navigation'] as Map<String, dynamic> : null;
        final vpr = nav?['via_primary_route'] is Map ? nav!['via_primary_route'] as Map<String, dynamic> : null;
        final onRouteVia = onRoute?['via_route'] is Map ? onRoute!['via_route'] as Map<String, dynamic> : null;
        final detourVia = bestDetour?['via_route'] is Map ? bestDetour!['via_route'] as Map<String, dynamic> : null;
        final primaryVia = choice == 'best_detour' ? detourVia : onRouteVia;
        var usedServerPrimaryRoute = false;
        // 1순위: 추천 카드 자체의 via_route (on_route/best_detour)
        if (primaryVia != null) {
          final parsed = _pathPointsFromServerJson(primaryVia['path_points']);
          if (parsed != null) {
            if (stLat != null && stLng != null) {
              await _maybeReplaceViaRouteFromClient(
                serverPts: parsed,
                serverSeg: _parsePathSegments(primaryVia['path_segments']),
                stLat: stLat,
                stLng: stLng,
                serverViaRoute: primaryVia,
                apply: (pts, seg) {
                  viaPathPoints = pts;
                  viaSegments = seg;
                },
              );
            } else {
              viaPathPoints = parsed;
              viaSegments = _parsePathSegments(primaryVia['path_segments']);
            }
            usedServerPrimaryRoute = true;
            _debugSegmentStats(
              label: 'primaryVia(on_route/best_detour)',
              pathSegments: viaSegments,
              pathPoints: viaPathPoints,
            );
          }
        }
        // 2순위: navigation.via_primary_route (레거시/폴백)
        if (!usedServerPrimaryRoute && vpr != null) {
          final parsed = _pathPointsFromServerJson(vpr['path_points']);
          if (parsed != null) {
            if (stLat != null && stLng != null) {
              await _maybeReplaceViaRouteFromClient(
                serverPts: parsed,
                serverSeg: _parsePathSegments(vpr['path_segments']),
                stLat: stLat,
                stLng: stLng,
                serverViaRoute: vpr,
                apply: (pts, seg) {
                  viaPathPoints = pts;
                  viaSegments = seg;
                },
              );
            } else {
              viaPathPoints = parsed;
              viaSegments = _parsePathSegments(vpr['path_segments']);
            }
            usedServerPrimaryRoute = true;
            _debugSegmentStats(
              label: 'navigation.via_primary_route',
              pathSegments: viaSegments,
              pathPoints: viaPathPoints,
            );
          }
        }
        if (!usedServerPrimaryRoute && stLat != null && stLng != null) {
          try {
            final vr = await ApiService().getDrivingRoute(
              startLat: _lastStartLat, startLng: _lastStartLng,
              goalLat: _destLat!, goalLng: _destLng!,
              waypointLat: stLat, waypointLng: stLng,
            );
            if (vr['success'] == true) {
              final parsed = _pathPointsFromServerJson(vr['path_points']);
              if (parsed != null) viaPathPoints = parsed;
              viaSegments = _parsePathSegments(vr['path_segments']);
              _debugSegmentStats(
                label: 'client.getDrivingRoute(fallback)',
                pathSegments: viaSegments,
                pathPoints: viaPathPoints,
              );
            }
          } catch (_) {}
        }

        // AI 추천 복원용 파라미터 저장
        final recAlts = data['alternatives'] is List ? data['alternatives'] as List : null;
        _lastRecPathPoints = viaPathPoints;
        _lastRecSegments = viaSegments;
        _lastRecStLat = stLat;
        _lastRecStLng = stLng;
        _lastRecStName = stName;
        _lastRecStPrice = stPrice;
        _lastRecSt2Lat = st2Lat;
        _lastRecSt2Lng = st2Lng;
        _lastRecSt2Name = st2Name;
        _lastRecSt2Price = st2Price;
        _lastRecStBrand = detourSt?['brand']?.toString();
        _lastRecSt2Brand = onRouteSt?['brand']?.toString();
        _lastRecAlternatives = recAlts;

        _drawResultOnMap(
          pathPoints: viaPathPoints,
          pathSegments: viaSegments,
          originLat: _lastStartLat,
          originLng: _lastStartLng,
          stLat: stLat,
          stLng: stLng,
          stName: stName,
          stPrice: stPrice,
          stBrand: _lastRecStBrand,
          st2Lat: st2Lat,
          st2Lng: st2Lng,
          st2Name: st2Name,
          st2Price: st2Price,
          st2Brand: _lastRecSt2Brand,
          destLat: _destLat!,
          destLng: _destLng!,
          alternatives: recAlts,
        );
      } else {
        final err = data['error'];
        final msg = err is Map ? err['message']?.toString() : null;
        setState(() => _errorMessage = msg ?? '분석 응답이 올바르지 않습니다.');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final raw = e.response?.data;
      String msg = '서버와 통신에 실패했습니다.';
      if (raw is Map) {
        final err = raw['error'];
        if (err is Map && err['message'] != null) msg = err['message'].toString();
      }
      setState(() => _errorMessage = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _aiAnalyzing = false);
    }
  }

  // ── 결과 마커 핀 아이콘 생성 (배지 + 아래 꼬리) ──
  Future<NOverlayImage> _resultMarkerIcon(String label, Color color) {
    const double badgeH = 24.0;
    const double triH = 6.0;
    const double fontSize = 11.0;
    const double hPad = 9.0;
    // 한글/숫자 평균 너비 기반 추정
    final double w = (label.length * 8.0 + hPad * 2).clamp(36.0, 110.0);
    final double totalH = badgeH + triH;

    return NOverlayImage.fromWidget(
      widget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: badgeH,
            width: w,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(badgeH / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(10, triH),
            painter: _DownTrianglePainter(color),
          ),
        ],
      ),
      size: Size(w, totalH),
      context: context,
    );
  }

  // ── 정체도(congestion) → 색상 변환 ──
  // 네이버 체감 톤에 가깝게 조정:
  // 1(원활)=초록, 2(서행)=노랑, 3(지체)=주황, 4(정체)=빨강
  static Color _congestionColor(int congestion) {
    switch (congestion) {
      case 1: return const Color(0xFF00B050); // 원활 (초록)
      case 2: return const Color(0xFFFFCC00); // 서행 (노랑)
      case 3: return const Color(0xFFFF8A00); // 지체 (주황)
      case 4: return const Color(0xFFE53935); // 정체 (빨강)
      default: return _kPrimary;              // 미확인 (앱 기본색)
    }
  }

  void _debugSegmentStats({
    required String label,
    List<Map<String, dynamic>>? pathSegments,
    required List<Map<String, dynamic>> pathPoints,
  }) {
    final segCount = pathSegments?.length ?? 0;
    final hist = <int, int>{};
    if (pathSegments != null) {
      for (final s in pathSegments) {
        final c = s['congestion'];
        if (c is num) {
          final k = c.toInt();
          hist[k] = (hist[k] ?? 0) + 1;
        }
      }
    }
    debugPrint(
      '[AI_MAP_SEGMENTS] $label '
      'path_points=${pathPoints.length} '
      'path_segments=$segCount '
      'congestion_hist=$hist',
    );
  }

  // ── 분석 결과 지도에 그리기 ──
  Future<void> _drawResultOnMap({
    required List<Map<String, dynamic>> pathPoints,
    List<Map<String, dynamic>>? pathSegments, // 교통 구간 데이터
    required double originLat,
    required double originLng,
    required double? stLat,
    required double? stLng,
    required String stName,
    int? stPrice,
    String? stBrand,
    double? st2Lat,
    double? st2Lng,
    String st2Name = '',
    int? st2Price,
    String? st2Brand,
    required double destLat,
    required double destLng,
    List<dynamic>? alternatives, // 대안 후보 (회색 마커)
  }) async {
    if (_mapController == null) return;

    // 브랜드 로고 캐시 완료 대기 (최대 2초)
    if (!_brandImagesCached) {
      await GasStationMapBadge.precacheBrandImages(context);
      _brandImagesCached = true;
    }

    await _mapController!.clearOverlays(type: NOverlayType.pathOverlay);
    await _mapController!.clearOverlays(type: NOverlayType.multipartPathOverlay);
    await _mapController!.clearOverlays(type: NOverlayType.arrowheadPathOverlay);
    await _mapController!.clearOverlays(type: NOverlayType.marker);

    // ── 경로 라인 ──
    if (pathSegments != null && pathSegments.isNotEmpty) {
      // ① NMultipartPathOverlay: 네이버 도로 폴리라인 그대로(출발 GPS를 끼워 넣지 않음 — 블록 가로지르는 직선 방지)
      final multiPaths = <NMultipartPath>[];

      for (int si = 0; si < pathSegments.length; si++) {
        final seg = pathSegments[si];
        final rawCoords = seg['coords'];
        if (rawCoords is! List || rawCoords.length < 2) continue;
        final coords = rawCoords
            .whereType<Map>()
            .map((c) => NLatLng(
                  (c['lat'] as num).toDouble(),
                  (c['lng'] as num).toDouble(),
                ))
            .toList();
        if (coords.length < 2) continue;
        final congestion = seg['congestion'] is num ? (seg['congestion'] as num).toInt() : 0;
        final color = _congestionColor(congestion);
        multiPaths.add(NMultipartPath(
          coords: coords,
          color: color,
          outlineColor: Colors.white.withValues(alpha: 0.9),
          passedColor: color.withValues(alpha: 0.4),
          passedOutlineColor: Colors.white.withValues(alpha: 0.4),
        ));
      }

      if (multiPaths.isNotEmpty) {
        await _mapController!.addOverlay(NMultipartPathOverlay(
          id: 'result_route_traffic',
          paths: multiPaths,
          width: 8,
          outlineWidth: 2,
        ));
      } else {
        debugPrint('[AI_MAP_SEGMENTS] path_segments 존재하지만 유효 coords가 없어 multipart 렌더 실패');
      }
    } else if (pathPoints.length >= 2) {
      debugPrint('[AI_MAP_SEGMENTS] path_segments 없음/비어있음 -> 단색 경로로 폴백');
      // 교통 세그먼트 없음: 네이버 ‘원활’ 구간과 동일한 초록 단색(구간색 있을 때와 톤 맞춤)
      final coords = pathPoints
          .map((p) => NLatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList();
      await _mapController!.addOverlay(NPathOverlay(
        id: 'result_route',
        coords: coords,
        color: _congestionColor(1),
        width: 8,
        outlineColor: Colors.white,
        outlineWidth: 2,
      ));
    }

    // 출발 핀: 길찾기 요청과 동일한 좌표(현재 위치 또는 사용자가 고른 출발지). 도로 스냅 없음.
    final originMarker = NMarker(
      id: 'result_origin',
      position: NLatLng(originLat, originLng),
      icon: await _resultMarkerIcon('출발', const Color(0xFF1B6B3A)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(originMarker);

    // 우회 최저가 마커 (파랑) — ai_result_screen 태그·비교 테이블과 동일
    if (stLat != null && stLng != null) {
      final stLabel = stPrice != null && stPrice > 0
          ? '${_wonFmt.format(stPrice)}원'
          : stName;
      const c = Color(0xFF1D6FE0);
      final stMarker = NMarker(
        id: 'result_station',
        position: NLatLng(stLat, stLng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: stLabel,
          brand: stBrand,
          borderColor: c,
          textColor: c,
          emphasizeBorder: true,
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      await _mapController!.addOverlay(stMarker);
    }

    // 경로상 최저가 마커 (주황) — AI 추천 강조색(_kMarkerRecommend)과 동일
    if (st2Lat != null && st2Lng != null && st2Name.isNotEmpty) {
      final st2Label = st2Price != null && st2Price > 0
          ? '${_wonFmt.format(st2Price)}원'
          : st2Name;
      const c2 = Color(0xFFE8700A);
      final st2Marker = NMarker(
        id: 'result_station2',
        position: NLatLng(st2Lat, st2Lng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: st2Label,
          brand: st2Brand,
          borderColor: c2,
          textColor: c2,
          emphasizeBorder: true,
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      await _mapController!.addOverlay(st2Marker);
    }

    // 목적지 마커 (빨강)
    final destMarker = NMarker(
      id: 'result_dest',
      position: NLatLng(destLat, destLng),
      icon: await _resultMarkerIcon('도착', const Color(0xFFB71C1C)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(destMarker);

    // 대안 후보 마커 (회색) — primary/secondary 위치와 겹치면 스킵
    final altLats = <double>[];
    final altLngs = <double>[];
    if (alternatives != null) {
      int altIdx = 0;
      for (final alt in alternatives) {
        if (alt is! Map) { altIdx++; continue; }
        final altSt = alt['station'] is Map ? alt['station'] as Map : null;
        if (altSt == null) { altIdx++; continue; }
        final altLat = altSt['lat'] is num ? (altSt['lat'] as num).toDouble() : null;
        final altLng = altSt['lng'] is num ? (altSt['lng'] as num).toDouble() : null;
        if (altLat == null || altLng == null) { altIdx++; continue; }
        final isNearPrimary = stLat != null && stLng != null &&
            (stLat - altLat).abs() < 0.0002 && (stLng - altLng).abs() < 0.0002;
        final isNearSecondary = st2Lat != null && st2Lng != null &&
            (st2Lat - altLat).abs() < 0.0002 && (st2Lng - altLng).abs() < 0.0002;
        if (!isNearPrimary && !isNearSecondary) {
          final altPriceRaw = altSt['price_won_per_liter'];
          final altPriceVal = altPriceRaw is num ? altPriceRaw.round() : null;
          final altLabel = altPriceVal != null ? '${_wonFmt.format(altPriceVal)}원' : '후보${altIdx + 1}';
          const altBorder = Color(0xFFDDDDDD);
          const altText = Color(0xFF1a1a1a);
          final altMarker = NMarker(
            id: 'result_alt_$altIdx',
            position: NLatLng(altLat, altLng),
            icon: await GasStationMapBadge.overlayImage(
              context,
              label: altLabel,
              brand: altSt['brand']?.toString(),
              borderColor: altBorder,
              textColor: altText,
              emphasizeBorder: false,
            ),
            anchor: const NPoint(0.5, 1.0),
          );
          await _mapController!.addOverlay(altMarker);
          altLats.add(altLat);
          altLngs.add(altLng);
        }
        altIdx++;
      }
    }

    // 카메라: 전체 경로가 보이도록 fitBounds
    final allLats = [
      originLat, destLat,
      if (stLat != null) stLat,
      if (st2Lat != null) st2Lat,
      ...altLats,
    ];
    final allLngs = [
      originLng, destLng,
      if (stLng != null) stLng,
      if (st2Lng != null) st2Lng,
      ...altLngs,
    ];
    final minLat = allLats.reduce(min);
    final maxLat = allLats.reduce(max);
    final minLng = allLngs.reduce(min);
    final maxLng = allLngs.reduce(max);

    _suppressCameraChange = true;
    await _mapController!.updateCamera(
      NCameraUpdate.fitBounds(
        NLatLngBounds(
          southWest: NLatLng(minLat, minLng),
          northEast: NLatLng(maxLat, maxLng),
        ),
        // 하단 패널(45%) 높이만큼 여백 확보
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 340),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _suppressCameraChange = false;
    });
  }

  /// EV 직접선택 모드 — 후보 충전소 마커를 지도에 표시
  Future<void> _drawEvCandidateMarkers(List<Map<String, dynamic>> candidates) async {
    if (_mapController == null || candidates.isEmpty) return;
    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final lat = (c['lat'] as num?)?.toDouble();
      final lng = (c['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final avail = (c['available_count'] as num?)?.toInt() ?? 0;
      final total = (c['total_count'] as num?)?.toInt() ?? 0;
      final name = c['name']?.toString() ?? '충전소';
      final label = '$avail/$total';
      final borderColor = avail > 0 ? const Color(0xFF1D9E75) : const Color(0xFFE8700A);
      final textColor   = avail > 0 ? const Color(0xFF1D9E75) : const Color(0xFFE8700A);
      final marker = NMarker(
        id: 'ev_candidate_$i',
        position: NLatLng(lat, lng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: label,
          isEv: true,
          borderColor: borderColor,
          textColor: textColor,
          emphasizeBorder: false,
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      marker.setOnTapListener((_) {
        // 탭하면 해당 충전소 상세 바텀시트 열기
        _openEvStationDetail(c);
      });
      await _mapController!.addOverlay(marker);
    }
  }

  /// EV AI 추천 결과 지도 마커 — 번개+avail/total 형태로 통일
  Future<void> _drawEvResultOnMap({
    required List<Map<String, dynamic>>? pathPoints,
    required List<Map<String, dynamic>>? pathSegments,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required Map<String, dynamic>? recommended,
    required List<Map<String, dynamic>> alternatives,
  }) async {
    if (_mapController == null) return;
    await _mapController!.clearOverlays();

    // 경로선 + 출발/도착 마커는 _drawResultOnMap 재사용 (stLat=null로 충전소 마커 생략)
    await _drawResultOnMap(
      pathPoints: pathPoints ?? [],
      pathSegments: pathSegments,
      originLat: originLat,
      originLng: originLng,
      stLat: null,
      stLng: null,
      stName: '',
      destLat: destLat,
      destLng: destLng,
    );

    // 출발 마커 (이미 _drawResultOnMap에서 그림 — EV 충전소 마커만 추가)
    // 추천 충전소 마커 (파랑 강조)
    if (recommended != null) {
      final lat = (recommended['lat'] as num?)?.toDouble();
      final lng = (recommended['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final avail = (recommended['available_count'] as num?)?.toInt() ?? 0;
        final total = (recommended['total_count'] as num?)?.toInt() ?? 0;
        const color = Color(0xFF1D6FE0);
        final marker = NMarker(
          id: 'ev_res_rec',
          position: NLatLng(lat, lng),
          icon: await GasStationMapBadge.overlayImage(
            context,
            label: '$avail/$total',
            isEv: true,
            borderColor: color,
            textColor: color,
            emphasizeBorder: true,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        await _mapController!.addOverlay(marker);
      }
    }

    // 대안 충전소 마커 (주황)
    for (int i = 0; i < alternatives.length; i++) {
      final alt = alternatives[i];
      final lat = (alt['lat'] as num?)?.toDouble();
      final lng = (alt['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final avail = (alt['available_count'] as num?)?.toInt() ?? 0;
      final total = (alt['total_count'] as num?)?.toInt() ?? 0;
      const color = Color(0xFFE8700A);
      final marker = NMarker(
        id: 'ev_res_alt_$i',
        position: NLatLng(lat, lng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: '$avail/$total',
          isEv: true,
          borderColor: color,
          textColor: color,
          emphasizeBorder: false,
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      await _mapController!.addOverlay(marker);
    }
  }

  /// 서버 `path_points` JSON → 지도용 좌표열
  static List<Map<String, dynamic>>? _pathPointsFromServerJson(dynamic raw) {
    if (raw is! List || raw.length < 2) return null;
    final parsed = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        final lat = e['lat'];
        final lng = e['lng'];
        if (lat is num && lng is num) {
          parsed.add({'lat': lat.toDouble(), 'lng': lng.toDouble()});
        }
      }
    }
    return parsed.length >= 2 ? parsed : null;
  }

  // ── path_segments JSON → Dart List 변환 헬퍼 ──
  static List<Map<String, dynamic>>? _parsePathSegments(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) result.add(Map<String, dynamic>.from(item));
    }
    return result.isEmpty ? null : result;
  }

  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthM = 6371000.0;
    final r1 = lat1 * pi / 180, r2 = lat2 * pi / 180;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(r1) * cos(r2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * asin(min(1.0, sqrt(a)));
    return earthM * c;
  }

  static int _closestPathPointIndex(List<Map<String, dynamic>> pts, double lat, double lng) {
    var bestI = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final d = _haversineMeters(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
        lat,
        lng,
      );
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI;
  }

  /// 폴리라인 순서상 목적지 구간이 경유 주유소보다 먼저 나오면(출발→목적→경유 형태) 의심한다.
  static bool _viaPolylineOrderSuspicious(
    List<Map<String, dynamic>> pts, {
    required double waypointLat,
    required double waypointLng,
    required double destLat,
    required double destLng,
  }) {
    if (pts.length < 4) return false;
    final iw = _closestPathPointIndex(pts, waypointLat, waypointLng);
    final id = _closestPathPointIndex(pts, destLat, destLng);
    final dW = _haversineMeters(
      (pts[iw]['lat'] as num).toDouble(),
      (pts[iw]['lng'] as num).toDouble(),
      waypointLat,
      waypointLng,
    );
    final dD = _haversineMeters(
      (pts[id]['lat'] as num).toDouble(),
      (pts[id]['lng'] as num).toDouble(),
      destLat,
      destLng,
    );
    const maxSnapM = 2500.0;
    if (dW > maxSnapM || dD > maxSnapM) return false;

    int? firstWithin(double alat, double alng, double radiusM) {
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i];
        if (_haversineMeters(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
              alat,
              alng,
            ) <=
            radiusM) {
          return i;
        }
      }
      return null;
    }

    const nearM = 400.0;
    final fDest = firstWithin(destLat, destLng, nearM);
    final fWay = firstWithin(waypointLat, waypointLng, nearM);
    if (fDest != null && fWay != null && fDest < fWay) return true;
    return id < iw;
  }

  /// charge_server `via_route.polyline_order.suspicious` (없으면 false)
  static bool _serverPolylineOrderSuspicious(Map<String, dynamic>? viaRoute) {
    if (viaRoute == null) return false;
    final po = viaRoute['polyline_order'];
    if (po is! Map) return false;
    return po['suspicious'] == true;
  }

  Future<void> _maybeReplaceViaRouteFromClient({
    required List<Map<String, dynamic>> serverPts,
    required List<Map<String, dynamic>>? serverSeg,
    required double stLat,
    required double stLng,
    /// 서버가 내려준 via_route 전체 (polyline_order 검사용)
    Map<String, dynamic>? serverViaRoute,
    required void Function(List<Map<String, dynamic>> pts, List<Map<String, dynamic>>? seg) apply,
  }) async {
    if (_destLat == null || _destLng == null) {
      apply(serverPts, serverSeg);
      return;
    }
    final serverSusp = _serverPolylineOrderSuspicious(serverViaRoute);
    final clientSusp = _viaPolylineOrderSuspicious(
      serverPts,
      waypointLat: stLat,
      waypointLng: stLng,
      destLat: _destLat!,
      destLng: _destLng!,
    );
    if (!serverSusp && !clientSusp) {
      apply(serverPts, serverSeg);
      return;
    }
    debugPrint(
      serverSusp
          ? '[AI_MAP_ROUTE] 서버 polyline_order.suspicious → 클라이언트 길찾기로 대체'
          : '[AI_MAP_ROUTE] 경유 경로 좌표 순서 의심 → 클라이언트 길찾기로 대체',
    );
    try {
      final vr = await ApiService().getDrivingRoute(
        startLat: _lastStartLat,
        startLng: _lastStartLng,
        goalLat: _destLat!,
        goalLng: _destLng!,
        waypointLat: stLat,
        waypointLng: stLng,
      );
      if (vr['success'] == true) {
        final parsed = _pathPointsFromServerJson(vr['path_points']);
        if (parsed != null) {
          final segs = _parsePathSegments(vr['path_segments']);
          apply(parsed, segs);
          return;
        }
      }
    } catch (_) {}
    apply(serverPts, serverSeg);
  }

  // ── 다른 후보 경로보기 ──
  Future<void> _showAltRouteOnMap(Map<String, dynamic> altItem) async {
    if (_destLat == null || _destLng == null) return;
    await _collapseResultSheetForMapFocus();
    final st = altItem['station'] is Map ? altItem['station'] as Map : null;
    if (st == null) return;
    final stLat = _asDouble(st['lat']);
    final stLng = _asDouble(st['lng']);
    if (stLat == null || stLng == null) return;
    final stName = st['name']?.toString() ?? '';
    final priceL = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : 0;

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    final vrMap = altItem['via_route'] is Map ? altItem['via_route'] as Map<String, dynamic> : null;
    var usedServerAlt = false;
    if (vrMap != null) {
      final parsed = _pathPointsFromServerJson(vrMap['path_points']);
      if (parsed != null) {
        await _maybeReplaceViaRouteFromClient(
          serverPts: parsed,
          serverSeg: _parsePathSegments(vrMap['path_segments']),
          stLat: stLat,
          stLng: stLng,
          serverViaRoute: vrMap,
          apply: (pts, seg) {
            pathPoints = pts;
            pathSegments = seg;
          },
        );
        usedServerAlt = true;
        _debugSegmentStats(
          label: 'alternative.via_route',
          pathSegments: pathSegments,
          pathPoints: pathPoints,
        );
      }
    }
    if (!usedServerAlt) {
      try {
        final vr = await ApiService().getDrivingRoute(
          startLat: _lastStartLat, startLng: _lastStartLng,
          goalLat: _destLat!, goalLng: _destLng!,
          waypointLat: stLat, waypointLng: stLng,
        );
        if (vr['success'] == true) {
          final parsed = _pathPointsFromServerJson(vr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _parsePathSegments(vr['path_segments']);
          _debugSegmentStats(
            label: 'alternative.client.getDrivingRoute(fallback)',
            pathSegments: pathSegments,
            pathPoints: pathPoints,
          );
        }
      } catch (_) {}
    }

    _drawResultOnMap(
      pathPoints: pathPoints,
      pathSegments: pathSegments,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      stLat: stLat,
      stLng: stLng,
      stName: stName,
      stPrice: priceL,
      stBrand: st['brand']?.toString(),
      st2Lat: _lastRecSt2Lat,
      st2Lng: _lastRecSt2Lng,
      st2Name: _lastRecSt2Name,
      st2Price: _lastRecSt2Price,
      st2Brand: _lastRecSt2Brand,
      destLat: _destLat!,
      destLng: _destLng!,
      alternatives: _lastRecAlternatives,
    );
  }

  // ── 비교 카드 탭 시 해당 경유 경로 지도에 그리기 ──
  Future<void> _showCompareCardRouteOnMap(Map<String, dynamic> stationData) async {
    if (_destLat == null || _destLng == null) return;
    await _collapseResultSheetForMapFocus();
    final st = stationData['station'] is Map ? stationData['station'] as Map : null;
    if (st == null) return;
    final stLat = _asDouble(st['lat']);
    final stLng = _asDouble(st['lng']);
    if (stLat == null || stLng == null) return;
    final stName = st['name']?.toString() ?? '';
    final priceL = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : 0;

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    final vrMap = stationData['via_route'] is Map ? stationData['via_route'] as Map<String, dynamic> : null;
    if (vrMap != null) {
      final parsed = _pathPointsFromServerJson(vrMap['path_points']);
      if (parsed != null) {
        await _maybeReplaceViaRouteFromClient(
          serverPts: parsed,
          serverSeg: _parsePathSegments(vrMap['path_segments']),
          stLat: stLat,
          stLng: stLng,
          serverViaRoute: vrMap,
          apply: (pts, seg) {
            pathPoints = pts;
            pathSegments = seg;
          },
        );
      }
    } else {
      try {
        final vr = await ApiService().getDrivingRoute(
          startLat: _lastStartLat, startLng: _lastStartLng,
          goalLat: _destLat!, goalLng: _destLng!,
          waypointLat: stLat, waypointLng: stLng,
        );
        if (vr['success'] == true) {
          final parsed = _pathPointsFromServerJson(vr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _parsePathSegments(vr['path_segments']);
        }
      } catch (_) {}
    }

    _drawResultOnMap(
      pathPoints: pathPoints,
      pathSegments: pathSegments,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      stLat: stLat,
      stLng: stLng,
      stName: stName,
      stPrice: priceL,
      stBrand: st['brand']?.toString(),
      destLat: _destLat!,
      destLng: _destLng!,
    );
  }

  Future<void> _runEvAnalyze() async {
    if (_destLat == null || _destLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지를 선택해 주세요.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final box = Hive.box(AppConstants.settingsBox);
    VehicleProfile? selectedVehicle;
    {
      final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded.map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>)).toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
            (v) => v?.id == selectedId, orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    if (selectedVehicle == null || !selectedVehicle.isEV) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전기차 프로필을 선택해 주세요.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      startLat = loc.lat;
      startLng = loc.lng;
    }

    setState(() { _aiAnalyzing = true; _errorMessage = null; });

    // 미리보기에서 이미 경로를 받아놨으면 재사용, 아니면 새로 fetch
    var pathPoints = _lastPathPoints.length >= 2 ? _lastPathPoints
        : <Map<String, dynamic>>[
            {'lat': startLat, 'lng': startLng},
            {'lat': _destLat!, 'lng': _destLng!},
          ];
    List<Map<String, dynamic>>? pathSegments = _lastPathSegments;
    int? directDurationMs;

    if (pathPoints.length < 2 || _lastStartLat != startLat || _lastStartLng != startLng) {
      try {
        final dr = await ApiService().getDrivingRoute(
          startLat: startLat, startLng: startLng,
          goalLat: _destLat!, goalLng: _destLng!,
        );
        if (dr['success'] == true) {
          if (dr['duration_ms'] is num) directDurationMs = (dr['duration_ms'] as num).round();
          final parsed = _pathPointsFromServerJson(dr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _parsePathSegments(dr['path_segments']);
          _lastStartLat = startLat;
          _lastStartLng = startLng;
          _lastPathPoints = pathPoints;
          _lastPathSegments = pathSegments;
        }
      } catch (_) {}
    }

    try {
      final data = await ApiService().postEvAiRecommend({
        'batteryPercent': selectedVehicle.currentLevelPercent,
        'batteryCapacityKwh': selectedVehicle.batteryCapacity,
        'efficiencyKmPerKwh': selectedVehicle.evEfficiency,
        'chargerType': _evChargerType,
        'originLat': startLat,
        'originLng': startLng,
        'destLat': _destLat,
        'destLng': _destLng,
        'pathPoints': pathPoints,
        if (directDurationMs != null) 'directDurationMs': directDurationMs,
        'highwayOnly': _evHighwayOnly,
      });

      if (!mounted) return;

      final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';

      setState(() {
        _isEvResultMode = true;
        _lastResultData = data;
        _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
      });

      // 지도에 경로 + 마커 그리기
      final recommended = data['recommended'] is Map ? data['recommended'] as Map<String, dynamic> : null;
      final alternatives = data['alternatives'] is List
          ? (data['alternatives'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      await _drawEvResultOnMap(
        pathPoints: pathPoints,
        pathSegments: pathSegments,
        originLat: startLat,
        originLng: startLng,
        destLat: _destLat!,
        destLng: _destLng!,
        recommended: recommended,
        alternatives: alternatives,
      );

    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '충전소 추천에 실패했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _aiAnalyzing = false);
    }
  }

  // EV 카드 "지도에서 경로 보기" 탭
  Future<void> _showEvStationRouteOnMap(Map<String, dynamic> station) async {
    if (_destLat == null || _destLng == null) return;
    await _collapseResultSheetForMapFocus();

    final stLat = (station['lat'] as num?)?.toDouble();
    final stLng = (station['lng'] as num?)?.toDouble();
    if (stLat == null || stLng == null) return;
    final stName = station['name']?.toString() ?? '';

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    try {
      final vr = await ApiService().getDrivingRoute(
        startLat: _lastStartLat, startLng: _lastStartLng,
        goalLat: _destLat!, goalLng: _destLng!,
        waypointLat: stLat, waypointLng: stLng,
      );
      if (vr['success'] == true) {
        final parsed = _pathPointsFromServerJson(vr['path_points']);
        if (parsed != null) pathPoints = parsed;
        pathSegments = _parsePathSegments(vr['path_segments']);
      }
    } catch (_) {}

    await _drawEvResultOnMap(
      pathPoints: pathPoints,
      pathSegments: pathSegments,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      destLat: _destLat!,
      destLng: _destLng!,
      recommended: station,
      alternatives: const [],
    );
    if (!mounted) return;

    if (_isEvSelectMode) {
      // 직접선택 리스트에서 호출 → 선택된 충전소 카드만 표시하고 시트 올리기
      setState(() {
        _prevEvSelectCandidates = List.of(_evSelectCandidates);
        _isEvSelectMode = false;
        _evSelectCandidates = [];
        _isEvResultMode = true;
        _lastResultData = {
          'charger_type': _evChargerType,
          'reachable_distance_km': 0.0,
          'recommended': station,
          'alternatives': <dynamic>[],
          'total_candidates': null,
          'filtered_out_count': 0,
        };
      });
      try {
        if (_sheetController.isAttached) {
          await _sheetController.animateTo(
            0.45,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      } catch (_) {}
    } else {
      // EV 결과 화면에서 호출 → 지도만 보이도록 시트 유지 (0.12), 데이터 유지
      if (mounted) setState(() => _isEvResultMapView = true);
    }
  }

  // EV 사용자 선택 모드 — 경로상 충전소 목록 불러오기
  Future<void> _runEvUserSelect() async {
    if (_destLat == null || _destLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지를 선택해 주세요.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final box = Hive.box(AppConstants.settingsBox);
    VehicleProfile? selectedVehicle;
    {
      final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded.map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>)).toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
            (v) => v?.id == selectedId, orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    if (selectedVehicle == null || !selectedVehicle.isEV) return;

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!; startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) return;
      startLat = loc.lat; startLng = loc.lng;
    }

    setState(() {
      _userSelecting = true;
      _userSelectingMessage = '경로상 충전소 목록 불러오는 중...';
      _errorMessage = null;
    });

    // 미리보기에서 이미 경로를 받아놨으면 재사용
    var pathPoints = _lastPathPoints.length >= 2 ? _lastPathPoints
        : <Map<String, dynamic>>[
            {'lat': startLat, 'lng': startLng},
            {'lat': _destLat!, 'lng': _destLng!},
          ];

    if (pathPoints.length < 2 || _lastStartLat != startLat || _lastStartLng != startLng) {
      try {
        final dr = await ApiService().getDrivingRoute(
          startLat: startLat, startLng: startLng,
          goalLat: _destLat!, goalLng: _destLng!,
        );
        if (dr['success'] == true) {
          final parsed = _pathPointsFromServerJson(dr['path_points']);
          if (parsed != null) pathPoints = parsed;
          _lastPathSegments = _parsePathSegments(dr['path_segments']);
          _lastStartLat = startLat;
          _lastStartLng = startLng;
          _lastPathPoints = pathPoints;
        }
      } catch (_) {}
    }

    try {
      final data = await ApiService().postEvAiRecommend({
        'batteryPercent': selectedVehicle.currentLevelPercent,
        'batteryCapacityKwh': selectedVehicle.batteryCapacity,
        'efficiencyKmPerKwh': selectedVehicle.evEfficiency,
        'chargerType': _evChargerType,
        'originLat': startLat,
        'originLng': startLng,
        'destLat': _destLat,
        'destLng': _destLng,
        'pathPoints': pathPoints,
        'userSelect': true,
        'highwayOnly': _evHighwayOnly,
      });
      if (!mounted) return;

      final candidates = data['candidates'] is List
          ? (data['candidates'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      if (candidates.isEmpty) {
        setState(() => _errorMessage = '경로 내 이용 가능한 충전소가 없어요.');
        return;
      }

      // 지도에 전체 후보 마커 표시
      final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';
      setState(() {
        _isEvSelectMode = true;
        _evSelectCandidates = candidates;
        _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
      });

      // 경로 + 출발/도착 마커 그리기 (후보 마커는 _drawEvCandidateMarkers에서 별도 처리)
      _drawResultOnMap(
        pathPoints: pathPoints,
        pathSegments: _lastPathSegments,
        originLat: startLat, originLng: startLng,
        stLat: null, stLng: null, stName: '',
        destLat: _destLat!, destLng: _destLng!,
        alternatives: null,
      );
      // EV 후보 마커 표시
      await _drawEvCandidateMarkers(candidates);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '충전소 목록을 불러오는데 실패했습니다.');
    } finally {
      if (mounted) setState(() => _userSelecting = false);
    }
  }

  // EV 사용자 선택 모드 — 리스트에서 충전소 탭 → 인라인 상세 바텀시트 (리스트 유지)
  Future<void> _openEvStationDetail(Map<String, dynamic> station) async {
    final statId = station['statId']?.toString();
    if (statId == null || !mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EvStationDetailSheet(
        station: station,
        stationId: statId,
        chargerType: _evChargerType,
        originLat: _originLat ?? _lastStartLat,
        originLng: _originLng ?? _lastStartLng,
        destLat: _destLat,
        destLng: _destLng,
        destName: _destName,
        onMapTap: () {
          Navigator.pop(ctx);
          _showEvStationRouteOnMap(station);
        },
      ),
    );
  }

  // ── EV UI 헬퍼 위젯 ──────────────────────────────────────────────────────
  Widget _evSegTab(String type, String label, IconData icon, Color activeColor) {
    final active = _evChargerType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _evChargerType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 1))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? activeColor : const Color(0xFF9EA7B2)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: active ? activeColor : const Color(0xFF9EA7B2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _evActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required bool loading,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? color : color.withOpacity(0.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: loading
            ? SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withOpacity(0.9)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _clearResult() async {
    // 모드 플래그를 먼저 동기적으로 리셋 → 뒤로가기 중복 호출 방지
    setState(() {
      _isResultMode = false;
      _isEvResultMode = false;
      _isEvSelectMode = false;
      _evSelectCandidates = [];
      _prevEvSelectCandidates = [];
      _isEvResultMapView = false;
      _isCompareResultMode = false;
      _isSelectMode = false;
      _isSelectSheetVisible = false;
      _lastResultData = null;
      _lastRouteSummary = null;
      _selectableStations = null;
      _selectedStationAId = null;
      _selectedStationBId = null;
      _sheetSize = 0.45;
    });
    await _mapController?.clearOverlays(type: NOverlayType.pathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.multipartPathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.arrowheadPathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.marker);
    _moveToMyLocation();
  }

  // ── AI 추천 경로로 복원 ──
  void _resetToAiRec() {
    if (_destLat == null || _destLng == null) return;
    _drawResultOnMap(
      pathPoints: _lastRecPathPoints,
      pathSegments: _lastRecSegments,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      stLat: _lastRecStLat,
      stLng: _lastRecStLng,
      stName: _lastRecStName,
      stPrice: _lastRecStPrice,
      stBrand: _lastRecStBrand,
      st2Lat: _lastRecSt2Lat,
      st2Lng: _lastRecSt2Lng,
      st2Name: _lastRecSt2Name,
      st2Price: _lastRecSt2Price,
      st2Brand: _lastRecSt2Brand,
      destLat: _destLat!,
      destLng: _destLng!,
      alternatives: _lastRecAlternatives,
    );
  }

  Future<void> _runUserSelect() async {
    if (_destLat == null || _destLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지를 선택해 주세요.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      startLat = loc.lat;
      startLng = loc.lng;
    }

    // 사용자 선택 시작 시 기존 AI/비교 결과 패널이 남아있지 않게 강제 초기화
    setState(() {
      _userSelecting = true;
      _userSelectingMessage = '경로상 주유소 목록 불러오는 중...';
      _errorMessage = null;
      _isResultMode = false;
      _isCompareResultMode = false;
      _lastResultData = null;
      _lastRouteSummary = null;
      _sheetSize = 0.45;
    });

    var pathPoints = <Map<String, dynamic>>[
      {'lat': startLat, 'lng': startLng},
      {'lat': _destLat!, 'lng': _destLng!},
    ];

    try {
      final dr = await ApiService().getDrivingRoute(
        startLat: startLat, startLng: startLng,
        goalLat: _destLat!, goalLng: _destLng!,
      );
      if (dr['success'] == true) {
        final raw = dr['path_points'];
        if (raw is List && raw.length >= 2) {
          final parsed = <Map<String, dynamic>>[];
          for (final e in raw) {
            if (e is Map) {
              final lat = e['lat']; final lng = e['lng'];
              if (lat is num && lng is num) {
                parsed.add({'lat': lat.toDouble(), 'lng': lng.toDouble()});
              }
            }
          }
          if (parsed.length >= 2) pathPoints = parsed;
        }
      }
    } catch (_) {}

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;

    // 경로상 주유소 목록 불러오기
    final box = Hive.box(AppConstants.settingsBox);
    final fuelCode = box.get(AppConstants.keyAiFuelType, defaultValue: FuelType.gasoline.code) as String;
    final tankCapacity = (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num).toDouble();
    final efficiency = (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num).toDouble();

    final body = <String, dynamic>{
      'vehicle_info': {
        'fuel_type': fuelCode,
        'tank_capacity_l': tankCapacity,
        'efficiency_km_per_l': efficiency,
      },
      'current_status': {
        'current_level_percent': _currentLevelPercent,
        'target_mode': 'FULL',
      },
      'route_context': {
        'origin': {'lat': startLat, 'lng': startLng},
        'destination': {'lat': _destLat, 'lng': _destLng},
        'path_points': pathPoints,
      },
    };

    try {
      final data = await ApiService().postRefuelRouteStations(body);
      if (!mounted) return;
      
      final stations = data['stations'] is List ? data['stations'] as List : [];
      if (stations.isEmpty) {
        setState(() => _userSelecting = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('경로상 주유소를 찾을 수 없습니다.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }

      final stationList = stations.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      setState(() {
        _userSelecting = false;
        _isSelectMode = true;
        _isSelectSheetVisible = true;
        _selectableStations = stationList;
        _selectedStationAId = null;
        _selectedStationBId = null;
      });

      // 지도에 경로와 주유소 마커 표시
      await _drawSelectModeMap();

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userSelecting = false;
        _errorMessage = '주유소 목록을 불러오는데 실패했습니다.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _onSymbolTapped(NSymbolInfo symbolInfo) {
    if (!_isSelectMode || _selectableStations == null) return;
    final tappedId = symbolInfo.caption;
    if (tappedId.isEmpty) return;

    // caption(=stId)로 어떤 주유소가 눌렸는지 확인
    final stationIds = <String>{
      for (int i = 0; i < _selectableStations!.length; i++)
        (_selectableStations![i]['id']?.toString() ?? '$i'),
    };
    if (!stationIds.contains(tappedId)) return;

    setState(() {
      final isA = _selectedStationAId == tappedId;
      final isB = _selectedStationBId == tappedId;

      if (isA) {
        _selectedStationAId = null;
      } else if (isB) {
        _selectedStationBId = null;
      } else {
        if (_selectedStationAId == null) {
          _selectedStationAId = tappedId;
        } else if (_selectedStationBId == null) {
          _selectedStationBId = tappedId;
        } else {
          // 3번째 선택이면 A를 교체
          _selectedStationAId = tappedId;
        }
      }
    });

    // 선택 변경에 맞춰 마커(라벨/색)도 즉시 갱신
    unawaited(_drawSelectModeMap());
  }

  Future<void> _drawSelectModeMap() async {
    if (_mapController == null || _selectableStations == null) return;

    await _mapController!.clearOverlays();

    // 경로 그리기
    if (_lastPathPoints.length >= 2) {
      final coords = _lastPathPoints.map((p) => NLatLng(p['lat'] as double, p['lng'] as double)).toList();
      final pathOverlay = NPathOverlay(
        id: 'select_route',
        coords: coords,
        color: const Color(0xFF1D9E75),
        width: 6,
        outlineColor: Colors.white,
        outlineWidth: 2,
      );
      await _mapController!.addOverlay(pathOverlay);
    }

    // 출발지 마커
    final originMarker = NMarker(
      id: 'select_origin',
      position: NLatLng(_lastStartLat, _lastStartLng),
      icon: await _resultMarkerIcon('출발', const Color(0xFF1B6B3A)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(originMarker);

    // 목적지 마커
    final destMarker = NMarker(
      id: 'select_dest',
      position: NLatLng(_destLat!, _destLng!),
      icon: await _resultMarkerIcon('목적지', const Color(0xFFB71C1C)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(destMarker);

    // 고속도로 필터 적용
    final visibleStations = _highwayFilterActive
        ? _selectableStations!.where((s) => s['is_highway_rest_area'] == true).toList()
        : _selectableStations!;

    // 최저가 ID 찾기
    String? cheapestId;
    int? cheapestPrice;
    for (final st in visibleStations) {
      final p = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : null;
      if (p != null && (cheapestPrice == null || p < cheapestPrice)) {
        cheapestPrice = p;
        cheapestId = st['id']?.toString();
      }
    }

    // 주유소 마커들: A=주황, B=파랑, 최저가=회색+"최저가", 기타=회색+가격
    for (int i = 0; i < visibleStations.length; i++) {
      final st = visibleStations[i];
      final stId = st['id']?.toString() ?? '$i';
      final lat = st['lat'] is num ? (st['lat'] as num).toDouble() : null;
      final lng = st['lng'] is num ? (st['lng'] as num).toDouble() : null;
      final price = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : null;

      if (lat != null && lng != null) {
        final isA = _selectedStationAId == stId;
        final isB = _selectedStationBId == stId;
        final isCheapest = cheapestId == stId && !isA && !isB;

        final String label;
        final Color borderColor;
        final Color textColor;
        final bool emphasize;
        final String? brand = st['brand']?.toString();
        if (isA) {
          label = price != null ? 'A ${_wonFmt.format(price)}원' : 'A';
          borderColor = const Color(0xFFE8700A);
          textColor = const Color(0xFFE8700A);
          emphasize = true;
        } else if (isB) {
          label = price != null ? 'B ${_wonFmt.format(price)}원' : 'B';
          borderColor = _kCompareBlue;
          textColor = _kCompareBlue;
          emphasize = true;
        } else if (isCheapest) {
          label = price != null ? '최저가 ${_wonFmt.format(price)}원' : '최저가';
          borderColor = const Color(0xFFEF4444);
          textColor = const Color(0xFFEF4444);
          emphasize = false;
        } else {
          label = price != null ? '${_wonFmt.format(price)}원' : '${i + 1}';
          borderColor = const Color(0xFFDDDDDD);
          textColor = const Color(0xFF1a1a1a);
          emphasize = false;
        }

        final marker = NMarker(
          id: 'select_station_$i',
          position: NLatLng(lat, lng),
          caption: NOverlayCaption(
            text: stId,
            textSize: 1,
            color: const Color(0x00000000),
            haloColor: const Color(0x00000000),
            minZoom: 22,
          ),
          icon: await GasStationMapBadge.overlayImage(
            context,
            label: label,
            brand: brand,
            borderColor: borderColor,
            textColor: textColor,
            emphasizeBorder: emphasize,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        marker.setOnTapListener((_) {
          if (!_isSelectMode || _selectableStations == null) return;
          final tappedId = stId;
          setState(() {
            final isA = _selectedStationAId == tappedId;
            final isB = _selectedStationBId == tappedId;
            if (isA) {
              _selectedStationAId = null;
            } else if (isB) {
              _selectedStationBId = null;
            } else {
              if (_selectedStationAId == null) {
                _selectedStationAId = tappedId;
              } else if (_selectedStationBId == null) {
                _selectedStationBId = tappedId;
              } else {
                _selectedStationAId = tappedId;
              }
            }
          });
          unawaited(_drawSelectModeMap());
        });
        await _mapController!.addOverlay(marker);
      }
    }

    // 카메라 이동 (필터된 목록 기준)
    final allLats = [_lastStartLat, _destLat!, ...visibleStations.map((s) {
      final lat = s['lat'];
      return lat is num ? lat.toDouble() : _lastStartLat;
    })];
    final allLngs = [_lastStartLng, _destLng!, ...visibleStations.map((s) {
      final lng = s['lng'];
      return lng is num ? lng.toDouble() : _lastStartLng;
    })];
    
    final minLat = allLats.reduce(min);
    final maxLat = allLats.reduce(max);
    final minLng = allLngs.reduce(min);
    final maxLng = allLngs.reduce(max);
    
    final bounds = NLatLngBounds(
      southWest: NLatLng(minLat, minLng),
      northEast: NLatLng(maxLat, maxLng),
    );
    
    await _mapController!.updateCamera(
      NCameraUpdate.fitBounds(bounds, padding: const EdgeInsets.all(80)),
    );
  }

  void _closeSelectSheet() {
    setState(() {
      _isSelectMode = false;
      _isSelectSheetVisible = false;
      _selectableStations = null;
      _highwayFilterActive = false;
      _selectedStationAId = null;
      _selectedStationBId = null;
    });
    _mapController?.clearOverlays();
  }

  Future<void> _runCompare() async {
    if (_selectedStationAId == null || _selectedStationBId == null) return;

    final stA = _selectableStations!.firstWhere((s) => s['id']?.toString() == _selectedStationAId);
    final stB = _selectableStations!.firstWhere((s) => s['id']?.toString() == _selectedStationBId);

    setState(() {
      _userSelecting = true;
      _userSelectingMessage = '선택한 2곳 비교 분석 중...';
      _isSelectSheetVisible = false; // 시트 닫기 (인라인)
    });
    
    final box = Hive.box(AppConstants.settingsBox);
    final fuelCode = box.get(AppConstants.keyAiFuelType, defaultValue: FuelType.gasoline.code) as String;
    final tankCapacity = (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num).toDouble();
    final efficiency = (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num).toDouble();
    
    final priceTarget = _targetMode == 'PRICE'
        ? (double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    final literTarget = _targetMode == 'LITER'
        ? (double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    final apiTargetValue = _targetMode == 'PRICE' ? priceTarget
        : (_targetMode == 'LITER' ? literTarget : 0.0);
    
    final body = <String, dynamic>{
      'vehicle_info': {
        'fuel_type': fuelCode,
        'tank_capacity_l': tankCapacity,
        'efficiency_km_per_l': efficiency,
      },
      'current_status': {
        'current_level_percent': _currentLevelPercent,
        'target_mode': _targetMode,
        'target_value': apiTargetValue,
      },
      'route_context': {
        'origin': {'lat': _lastStartLat, 'lng': _lastStartLng},
        'destination': {'lat': _destLat!, 'lng': _destLng!},
        'path_points': _lastPathPoints,
      },
      // 서버 validateComparePayload는 `stations`(길이 2)만 받음
      'stations': [stA, stB],
    };
    
    try {
      final data = await ApiService().postRefuelCompare(body);
      if (!mounted) return;
      
      setState(() {
        _userSelecting = false;
        _isResultMode = false;
        _isCompareResultMode = true;
        _isSelectMode = false;
        _isSelectSheetVisible = false;
        _lastResultData = data;
        final originLabel = _originName ?? _currentLocationAddress ?? '출발지';
        _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
      });

      // 비교 결과 지도에 표시
      await _drawCompareResultMap(data);

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userSelecting = false;
        _isSelectSheetVisible = true; // 실패하면 시트 복원
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('비교 실패: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _drawCompareResultMap(Map<String, dynamic> data) async {
    // 비교 결과 지도 그리기 (간단 버전)
    if (_mapController == null) return;
    
    await _mapController!.clearOverlays();
    
    // 경로
    if (_lastPathPoints.length >= 2) {
      final coords = _lastPathPoints.map((p) => NLatLng(p['lat'] as double, p['lng'] as double)).toList();
      final pathOverlay = NPathOverlay(
        id: 'compare_route',
        coords: coords,
        color: const Color(0xFF1D9E75),
        width: 6,
        outlineColor: Colors.white,
        outlineWidth: 2,
      );
      await _mapController!.addOverlay(pathOverlay);
    }
    
    // 출발지/목적지 마커
    final originMarker = NMarker(
      id: 'compare_origin',
      position: NLatLng(_lastStartLat, _lastStartLng),
      icon: await _resultMarkerIcon('출발', const Color(0xFF1B6B3A)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(originMarker);
    
    final destMarker = NMarker(
      id: 'compare_dest',
      position: NLatLng(_destLat!, _destLng!),
      icon: await _resultMarkerIcon('목적지', const Color(0xFFB71C1C)),
      anchor: const NPoint(0.5, 1.0),
    );
    await _mapController!.addOverlay(destMarker);
    
    // A, B 주유소 마커
    final stAData = data['station_a'] is Map ? data['station_a'] as Map : null;
    final stBData = data['station_b'] is Map ? data['station_b'] as Map : null;
    final winner = data['comparison'] is Map ? (data['comparison'] as Map)['winner']?.toString() : null;
    
    if (stAData != null) {
      final lat = stAData['lat'] is num ? (stAData['lat'] as num).toDouble() : null;
      final lng = stAData['lng'] is num ? (stAData['lng'] as num).toDouble() : null;
      if (lat != null && lng != null) {
        final isWin = winner == 'station_a';
        final color = isWin ? const Color(0xFFE8700A) : const Color(0xFF1D6FE0);
        final p = stAData['price_won_per_liter'] is num
            ? (stAData['price_won_per_liter'] as num).round()
            : null;
        final label = p != null ? 'A ${_wonFmt.format(p)}원' : 'A';
        final marker = NMarker(
          id: 'compare_a',
          position: NLatLng(lat, lng),
          icon: await GasStationMapBadge.overlayImage(
            context,
            label: label,
            brand: stAData['brand']?.toString(),
            borderColor: color,
            textColor: color,
            emphasizeBorder: isWin,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        await _mapController!.addOverlay(marker);
      }
    }

    if (stBData != null) {
      final lat = stBData['lat'] is num ? (stBData['lat'] as num).toDouble() : null;
      final lng = stBData['lng'] is num ? (stBData['lng'] as num).toDouble() : null;
      if (lat != null && lng != null) {
        final isWin = winner == 'station_b';
        final color = isWin ? const Color(0xFFE8700A) : const Color(0xFF1D6FE0);
        final p = stBData['price_won_per_liter'] is num
            ? (stBData['price_won_per_liter'] as num).round()
            : null;
        final label = p != null ? 'B ${_wonFmt.format(p)}원' : 'B';
        final marker = NMarker(
          id: 'compare_b',
          position: NLatLng(lat, lng),
          icon: await GasStationMapBadge.overlayImage(
            context,
            label: label,
            brand: stBData['brand']?.toString(),
            borderColor: color,
            textColor: color,
            emphasizeBorder: isWin,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        await _mapController!.addOverlay(marker);
      }
    }
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('앱 종료'),
        content: const Text('앱을 종료하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop();
            },
            child: const Text('종료', style: TextStyle(color: Color(0xFFE24B4A))),
          ),
        ],
      ),
    );
  }

  void _showLevelEditSheet({bool isEv = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LevelEditSheet(
        initialLevel: _currentLevelPercent,
        initialMode: _targetMode,
        priceController: _priceController,
        literController: _literController,
        isEv: isEv,
        onSave: (level, mode) {
          setState(() { _currentLevelPercent = level; _targetMode = mode; });
          final box = Hive.box(AppConstants.settingsBox);
          _saveVehicleLevel(box, level: level, mode: mode);
          // 글로벌 fallback도 유지
          box.put(AppConstants.keyAiCurrentLevelPercent, level);
          box.put(AppConstants.keyAiTargetMode, mode);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final canGasAnalysis = settings.vehicleType != VehicleType.ev;
    final canEvAnalysis = settings.vehicleType != VehicleType.gas;
    if ((_aiAnalysisType == 'gas' && !canGasAnalysis) || (_aiAnalysisType == 'ev' && !canEvAnalysis)) {
      _aiAnalysisType = canGasAnalysis ? 'gas' : 'ev';
    }

    // AI 탭(index 2)에 진입할 때마다 지도를 내 위치로 이동 + 주소 재로드
    ref.listen(bottomNavIndexProvider, (prev, next) {
      if (next == 2 && prev != 2) {
        // AI 탭 재진입 시 온보딩 플래그 리셋 — 차량 등록 없이 뒤로가기 후 재진입할 때 다시 온보딩 표시
        _onboardingPushed = false;
        if (_mapController != null) _moveToMyLocation();
        if (_currentLocationAddress == null) _loadCurrentAddress();
      }
    });

    if (!settings.aiOnboardingDone) {
      // AI 탭이 실제로 선택됐을 때만 온보딩 표시 (IndexedStack에서 미리 빌드되는 것 방지)
      final currentTab = ref.watch(bottomNavIndexProvider);
      if (currentTab == 2 && !_onboardingPushed) {
        _onboardingPushed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const AiOnboardingScreen()),
          );
        });
      }
      return const Scaffold(backgroundColor: Colors.white);
    }

    final box = Hive.box(AppConstants.settingsBox);
    final fuelCode = box.get(AppConstants.keyAiFuelType, defaultValue: FuelType.gasoline.code) as String;
    final tankCapacity = (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num).toDouble();
    final efficiency = (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num).toDouble();
    final fuelLabel = FuelType.fromCode(fuelCode).label;

    // 멀티 차량 — 선택된 차량 프로필
    VehicleProfile? selectedVehicle;
    {
      final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null && selectedId != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded.map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>)).toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
            (v) => v?.id == selectedId, orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    final isEvVehicle = selectedVehicle?.isEV ?? false;

    // 선택 차량에 따라 분석 타입 자동 동기화
    final expectedType = isEvVehicle ? 'ev' : 'gas';
    if (_aiAnalysisType != expectedType) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {
          _aiAnalysisType = expectedType;
          // 차량 타입이 바뀌면 이전 모드 플래그 전체 초기화
          _isResultMode = false;
          _isEvResultMode = false;
          _isEvSelectMode = false;
          _evSelectCandidates = [];
          _isCompareResultMode = false;
          _isSelectMode = false;
          _isSelectSheetVisible = false;
          _lastResultData = null;
          _lastRouteSummary = null;
          _selectableStations = null;
          _selectedStationAId = null;
          _selectedStationBId = null;
        });
        _mapController?.clearOverlays();
      });
    }

    // 차량 전환 감지 → 슬라이더/목표 값을 해당 차량 프로필 기준으로 갱신
    if (selectedVehicle != null && selectedVehicle.id != _lastSyncedVehicleId) {
      final sv = selectedVehicle!;
      _lastSyncedVehicleId = sv.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _currentLevelPercent = sv.currentLevelPercent;
          _targetMode = sv.targetMode;
          _priceController.text = sv.targetValue.toStringAsFixed(0);
        });
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // AI 탭이 현재 선택된 탭이 아니면 처리하지 않음
        // (IndexedStack에서 숨겨진 상태에도 PopScope가 살아있어 HomeScreen과 중복 트리거 방지)
        if (ref.read(bottomNavIndexProvider) != 2) return;
        void markHandled() => _lastInScreenBackHandledAt = DateTime.now();

        final recentlyHandled = _lastInScreenBackHandledAt != null &&
            DateTime.now().difference(_lastInScreenBackHandledAt!) <
                const Duration(milliseconds: 700);
        // 1. 주유소 선택 모드
        if (_isSelectMode) {
          markHandled();
          setState(() {
            _isSelectMode = false;
            _isSelectSheetVisible = false;
            _selectableStations = null;
            _selectedStationAId = null;
            _selectedStationBId = null;
          });
          _mapController?.clearOverlays();
          return;
        }
        // 2. 피커 모드
        if (_isPickerMode) {
          markHandled();
          _exitPickerMode();
          return;
        }
        // 3. 비교 결과 모드
        if (_isCompareResultMode) {
          markHandled();
          _clearResult();
          return;
        }
        // 4. AI 결과 모드 / EV 선택 모드
        if (_isResultMode || _isEvResultMode || _isEvSelectMode) {
          markHandled();
          // 직접선택 경로 보기에서 EV 결과 모드로 전환된 경우 → 리스트로 복원
          if (_isEvResultMode && _prevEvSelectCandidates.isNotEmpty) {
            setState(() {
              _isEvResultMode = false;
              _isEvSelectMode = true;
              _evSelectCandidates = _prevEvSelectCandidates;
              _prevEvSelectCandidates = [];
            });
            // 후보 마커 + 기존 경로 다시 그리기
            _mapController?.clearOverlays(type: NOverlayType.pathOverlay);
            _mapController?.clearOverlays(type: NOverlayType.multipartPathOverlay);
            _mapController?.clearOverlays(type: NOverlayType.marker);
            _drawResultOnMap(
              pathPoints: _lastPathPoints,
              pathSegments: _lastPathSegments,
              originLat: _lastStartLat, originLng: _lastStartLng,
              stLat: null, stLng: null, stName: '',
              destLat: _destLat!, destLng: _destLng!,
            );
            _drawEvCandidateMarkers(_evSelectCandidates);
            return;
          }
          // EV 결과 화면에서 지도보기 중이면 → 결과 시트 복원
          if (_isEvResultMode && _isEvResultMapView) {
            setState(() => _isEvResultMapView = false);
            // 원본 추천 결과로 지도 다시 그리기
            final rec = _lastResultData?['recommended'] is Map
                ? _lastResultData!['recommended'] as Map<String, dynamic>
                : null;
            final alts = _lastResultData?['alternatives'] is List
                ? (_lastResultData!['alternatives'] as List).whereType<Map<String, dynamic>>().toList()
                : <Map<String, dynamic>>[];
            unawaited(_drawEvResultOnMap(
              pathPoints: _lastPathPoints,
              pathSegments: _lastPathSegments,
              originLat: _lastStartLat,
              originLng: _lastStartLng,
              destLat: _destLat!,
              destLng: _destLng!,
              recommended: rec,
              alternatives: alts,
            ));
            unawaited(Future(() async {
              try {
                if (_sheetController.isAttached) {
                  await _sheetController.animateTo(
                    0.45,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              } catch (_) {}
            }));
            return;
          }
          _clearResult();
          return;
        }
        // 4-1. 오류 메시지 초기화
        if (_errorMessage != null) {
          markHandled();
          setState(() => _errorMessage = null);
          return;
        }
        // 5. 목적지 초기화
        if (_destLat != null && _destLng != null) {
          markHandled();
          setState(() {
            _destLat = null;
            _destLng = null;
            _destName = null;
          });
          _mapController?.clearOverlays();
          return;
        }
        // 6. 출발지 초기화
        if (_originLat != null && _originLng != null) {
          markHandled();
          setState(() {
            _originLat = null;
            _originLng = null;
            _originName = null;
          });
          return;
        }
        // 같은 뒤로가기 입력에서 콜백이 중복 트리거되는 경우 종료 다이얼로그를 막는다.
        if (recentlyHandled) return;
        // AI 탭의 완전 초기 화면에서만 종료 확인을 띄운다.
        final isAiFirstScreen = !_isPickerMode &&
            !_isSelectMode &&
            !_isResultMode &&
            !_isEvResultMode &&
            !_isEvSelectMode &&
            !_isCompareResultMode &&
            !_aiAnalyzing &&
            !_userSelecting &&
            _errorMessage == null &&
            _originLat == null &&
            _originLng == null &&
            _originName == null &&
            _destLat == null &&
            _destLng == null &&
            _destName == null;
        if (!isAiFirstScreen) return;
        // 7. 앱 종료 확인 (중복 트리거 방지용 markHandled 선호출)
        markHandled();
        _showExitDialog();
      },
      child: Scaffold(
      body: Stack(
        children: [
          // ── 배경 지도 ──
          NaverMap(
            options: NaverMapViewOptions(
              mapType: NMapType.basic,
              locationButtonEnable: false,
              // 사용자 선택 모드에서는 심볼(주유소 마커) 탭을 잡아서
              // 리스트 A/B 선택과 동기화한다.
              consumeSymbolTapEvents: _isSelectMode,
            ),
            onMapReady: _onMapReady,
            onCameraIdle: _onCameraIdle,
            onSymbolTapped: _onSymbolTapped,
            onCameraChange: (_, __) {
              if (_suppressCameraChange) return;
              // 일반 모드: 카메라 이동 시 내 위치 표시 해제
              if (!_isPickerMode) {
                if (_isAtMyLocation) setState(() => _isAtMyLocation = false);
                return;
              }
              // 피커 모드에서 드래그 중 역지오코딩 준비 표시
              setState(() => _isReverseGeocoding = true);
              _reverseGeocodeDebounce?.cancel();
              // 디바운스 후 controller에서 현재 카메라 위치 읽어 역지오코딩
              _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 500), () async {
                if (_mapController == null || !mounted) return;
                final camPos = await _mapController!.getCameraPosition();
                if (!mounted) return;
                setState(() => _pickerLatLng = camPos.target);
                final addr = await ApiService().reverseGeocode(
                    camPos.target.latitude, camPos.target.longitude);
                if (mounted) {
                  setState(() {
                    _pickerAddress = addr ?? '주소를 가져올 수 없습니다';
                    _isReverseGeocoding = false;
                  });
                }
              });
            },
          ),

          // ── 피커 모드: 가운데 핀 ──
          if (_isPickerMode)
            IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_pin, size: 52, color: _pickingOrigin ? _kPrimary : _kDanger),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),

          // ── 피커 모드: 상단 힌트 ──
          if (_isPickerMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12)],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_location_alt_rounded,
                          color: _pickingOrigin ? _kPrimary : _kDanger,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _pickingOrigin ? '지도에서 출발지를 선택하세요' : '지도에서 목적지를 선택하세요',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── 피커 모드: 하단 주소 + 확인/취소 ──
          if (_isPickerMode)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded,
                                color: _pickingOrigin ? _kPrimary : _kDanger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _isReverseGeocoding
                                  ? const Text('주소 확인 중...',
                                      style: TextStyle(fontSize: 13, color: Color(0xFF999999)))
                                  : Text(
                                      _pickerAddress ?? '지도를 드래그하세요',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _exitPickerMode,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFDDDDDD)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('취소', style: TextStyle(color: Color(0xFF666666))),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: (_pickerLatLng != null && !_isReverseGeocoding)
                                    ? _confirmMapPick : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _pickingOrigin ? _kPrimary : _kDanger,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('이 위치로 설정',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── 일반 모드: 상단 오버레이 ──
          if (!_isPickerMode && !_isResultMode && !_isEvResultMode && !_isEvSelectMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 상단 분석 레이블 + 차량 버튼
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isEvVehicle ? Icons.bolt_rounded : Icons.local_gas_station_rounded,
                                    size: 15,
                                    color: isEvVehicle ? _kCompareBlue : _kPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isEvVehicle ? 'AI 충전 분석' : 'AI 주유 분석',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isEvVehicle ? _kCompareBlue : _kPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const AiVehicleListScreen()));
                              setState(() {});
                            },
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                              ),
                              child: const Icon(Icons.directions_car_rounded, color: Color(0xFF666666), size: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 경로 입력 카드
                      _RouteCard(
                        originName: _originName,
                        destName: _destName,
                        currentLocationAddress: _currentLocationAddress,
                        onTapOrigin: () => _showLocationSheet(isOrigin: true),
                        onTapDest: () => _showLocationSheet(isOrigin: false),
                        onClearOrigin: () => setState(() {
                          _originName = null; _originLat = null; _originLng = null;
                        }),
                        onClearDest: () => setState(() {
                          _destName = null; _destLat = null; _destLng = null; _errorMessage = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 일반 모드: 하단 패널 ──
          if (!_isPickerMode && !_isResultMode && !_isEvResultMode && !_isEvSelectMode && !_isSelectMode)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 에러 메시지
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kDanger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: _kDanger, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMessage!,
                                    style: const TextStyle(fontSize: 12, color: _kDanger)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // 잔량 + 차량 미니 카드
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showLevelEditSheet(isEv: isEvVehicle),
                              child: _LevelSummaryCard(
                                currentLevel: _currentLevelPercent,
                                targetMode: _targetMode,
                                priceController: _priceController,
                                literController: _literController,
                                wonFmt: _wonFmt,
                                isEv: isEvVehicle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const AiVehicleListScreen()));
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isEvVehicle
                                      ? const Color(0xFF1D6FE0).withOpacity(0.4)
                                      : const Color(0xFFEEEEEE),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isEvVehicle ? Icons.bolt_rounded : Icons.local_gas_station_rounded,
                                        size: 13,
                                        color: isEvVehicle ? const Color(0xFF1D6FE0) : _kPrimary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        selectedVehicle?.name.isNotEmpty == true
                                            ? selectedVehicle!.name
                                            : (isEvVehicle ? '차량 선택' : fuelLabel),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isEvVehicle ? const Color(0xFF1D6FE0) : _kPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isEvVehicle
                                        ? '· ${(selectedVehicle?.evEfficiency ?? efficiency).toStringAsFixed(1)}km/kWh'
                                        : '· ${efficiency.toStringAsFixed(1)}km/L',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                                  ),
                                  Text(
                                    isEvVehicle
                                        ? '· ${(selectedVehicle?.batteryCapacity ?? tankCapacity).toStringAsFixed(0)}kWh'
                                        : '· ${tankCapacity.toStringAsFixed(0)}L',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isEvVehicle) ...[
                        // ── EV 옵션 + 액션 통합 카드 ──
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE4ECF7)),
                          ),
                          child: Column(
                            children: [
                              // 급속 / 완속 세그먼트
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                                child: Container(
                                  height: 44,
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5FB),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Row(
                                    children: [
                                      _evSegTab('FAST', '급속', Icons.bolt_rounded, _kCompareBlue),
                                      _evSegTab('SLOW', '완속', Icons.electrical_services_rounded, _kPrimary),
                                    ],
                                  ),
                                ),
                              ),
                              // 구분선
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Divider(height: 1, color: Color(0xFFF0F0F0)),
                              ),
                              // 고속도로만 칩 + 버튼들
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                child: Row(
                                  children: [
                                    // 고속도로만 토글칩
                                    GestureDetector(
                                      onTap: () => setState(() => _evHighwayOnly = !_evHighwayOnly),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _evHighwayOnly
                                              ? _kCompareBlue.withOpacity(0.08)
                                              : const Color(0xFFF5F7FA),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _evHighwayOnly
                                                ? _kCompareBlue.withOpacity(0.6)
                                                : const Color(0xFFE0E0E0),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add_road_rounded, size: 13,
                                              color: _evHighwayOnly ? _kCompareBlue : const Color(0xFFAAAAAA)),
                                            const SizedBox(width: 4),
                                            Text('고속도로만',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _evHighwayOnly ? _kCompareBlue : const Color(0xFF999999),
                                              )),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    // AI 추천
                                    _evActionBtn(
                                      label: 'AI 추천',
                                      icon: Icons.auto_awesome_rounded,
                                      color: _kCompareBlue,
                                      loading: _aiAnalyzing,
                                      enabled: !_aiAnalyzing && !_userSelecting,
                                      onTap: _runEvAnalyze,
                                    ),
                                    const SizedBox(width: 7),
                                    // 직접 선택
                                    _evActionBtn(
                                      label: '직접 선택',
                                      icon: Icons.format_list_bulleted_rounded,
                                      color: const Color(0xFF3D8B6E),
                                      loading: _userSelecting,
                                      enabled: !_aiAnalyzing && !_userSelecting,
                                      onTap: _runEvUserSelect,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // AI 분석 / 사용자 선택 버튼 (주유 전용)
                      if (!isEvVehicle) Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: (_aiAnalyzing || _userSelecting)
                                    ? null
                                    : _runAnalyze,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kPrimary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _kPrimary.withOpacity(0.55),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, size: 18),
                                          SizedBox(width: 6),
                                          Text('AI 주유소 추천',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: (_aiAnalyzing || _userSelecting)
                                    ? null
                                    : _runUserSelect,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kCompareBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _kCompareBlue.withOpacity(0.55),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: _userSelecting
                                    ? const SizedBox(height: 22, width: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.compare_arrows_rounded, size: 18),
                                          SizedBox(width: 6),
                                          Text('사용자 선택',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 결과 모드: 상단 뒤로가기 + 경로 요약 ──
          if (_isResultMode || _isEvResultMode || _isEvSelectMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _clearResult,
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )],
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              size: 18, color: Color(0xFF1a1a1a)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )],
                          ),
                          child: Text(
                            _lastRouteSummary ?? '분석 결과',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1a1a1a)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 결과 모드: 드래그 가능한 분석 결과 패널 ──
          if ((_isResultMode || _isCompareResultMode || _isEvResultMode) && _lastResultData != null)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.45,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.12, 0.45, 0.9],
              builder: (_, sc) {
                _resultSheetScrollController = sc;
                return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: _isEvResultMode
                    ? EvResultBody(
                        data: _lastResultData!,
                        scrollController: sc,
                        onStationMapTap: _showEvStationRouteOnMap,
                        originLat: _lastStartLat,
                        originLng: _lastStartLng,
                        destLat: _destLat,
                        destLng: _destLng,
                        destName: _destName ?? '목적지',
                      )
                    : _isCompareResultMode
                        ? CompareResultBody(
                            data: _lastResultData!,
                            destinationName: _destName ?? '목적지',
                            scrollController: sc,
                            wonFmt: _wonFmt,
                            fuelLabel: fuelLabel,
                            originLat: _lastStartLat,
                            originLng: _lastStartLng,
                            destLat: _destLat,
                            destLng: _destLng,
                            onCardTap: _showCompareCardRouteOnMap,
                          )
                        : AiResultBody(
                            data: _lastResultData!,
                            destinationName: _destName ?? '목적지',
                            originLat: _lastStartLat,
                            originLng: _lastStartLng,
                            scrollController: sc,
                            onAltRouteView: _showAltRouteOnMap,
                            onResetToAiRec: _resetToAiRec,
                          ),
                );
              },
            ),

          // ── EV 충전소 선택 모드: 하단 리스트 시트 ──
          if (_isEvSelectMode && _evSelectCandidates.isNotEmpty)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.45,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.12, 0.45, 0.9],
              builder: (_, sc) {
                _resultSheetScrollController = sc;
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, -2))],
                  ),
                  child: EvSelectList(
                    candidates: _evSelectCandidates,
                    chargerType: _evChargerType,
                    scrollController: sc,
                    onSelect: _openEvStationDetail,
                  ),
                );
              },
            ),

          // ── 현재위치 버튼 (결과 모드: 시트 위에 붙어 이동) ──
          if (_isResultMode || _isEvResultMode || _isEvSelectMode)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom +
                  MediaQuery.of(context).size.height * _sheetSize + 12,
              child: GestureDetector(
                onTap: _moveToMyLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: (_isLocating || _isAtMyLocation)
                        ? _kPrimary
                        : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )],
                  ),
                  child: _isLocating
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.my_location_rounded,
                          size: 22,
                          color: _isAtMyLocation
                              ? Colors.white
                              : const Color(0xFF666666)),
                ),
              ),
            ),

          // ── 사용자 선택 모드: 인라인 드래그 가능 시트 ──
          if (_isSelectMode && _isSelectSheetVisible && _selectableStations != null)
            DraggableScrollableSheet(
              controller: _selectSheetCtrl,
              initialChildSize: 0.45,
              minChildSize: 0.14,
              maxChildSize: 0.88,
              snap: true,
              snapSizes: const [0.14, 0.45, 0.88],
              builder: (_, sc) => _StationSelectInlineSheet(
                sheetScrollCtrl: sc,
                stations: _selectableStations!,
                selectedAId: _selectedStationAId,
                selectedBId: _selectedStationBId,
                wonFmt: _wonFmt,
                isComparing: _userSelecting,
                onStationTap: (stId) {
                  setState(() {
                    final isA = _selectedStationAId == stId;
                    final isB = _selectedStationBId == stId;
                    if (isA) {
                      _selectedStationAId = null;
                    } else if (isB) {
                      _selectedStationBId = null;
                    } else if (_selectedStationAId == null) {
                      _selectedStationAId = stId;
                    } else if (_selectedStationBId == null) {
                      _selectedStationBId = stId;
                    } else {
                      _selectedStationAId = stId;
                    }
                  });
                  unawaited(_drawSelectModeMap());
                },
                onCompare: _runCompare,
                onClose: _closeSelectSheet,
                onHighwayFilterChanged: (v) {
                  setState(() => _highwayFilterActive = v);
                  unawaited(_drawSelectModeMap());
                },
              ),
            ),

          // ── 일반 모드: 현재위치 버튼 (우하단) ──
          if (!_isPickerMode && !_isResultMode && !_isEvResultMode && !_isEvSelectMode && !_isSelectMode)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + (isEvVehicle ? 290 : 210),
              child: GestureDetector(
                onTap: _moveToMyLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_isLocating || _isAtMyLocation) ? _kPrimary : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isLocating
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.my_location_rounded,
                          size: 22,
                          color: _isAtMyLocation
                              ? Colors.white
                              : const Color(0xFF666666)),
                ),
              ),
            ),

          // ── AI 경로 추천 로딩 오버레이 ──
          if (_aiAnalyzing)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: _aiAnalysisType == 'ev' ? _kCompareBlue : _kPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _aiAnalysisType == 'ev' ? 'AI 충전소 추천 중...' : 'AI 주유소 추천 중...',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1a1a1a),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── 비교 분석 로딩 오버레이 ──
          if (_userSelecting)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: _kCompareBlue,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            _userSelectingMessage,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1a1a1a),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ), // Scaffold
    ); // PopScope
  }
}

// ─── 사용자 선택 인라인 시트 ────────────────────────────────────────────────────

class _StationSelectInlineSheet extends StatefulWidget {
  final ScrollController sheetScrollCtrl;
  final List<Map<String, dynamic>> stations;
  final String? selectedAId;
  final String? selectedBId;
  final NumberFormat wonFmt;
  final bool isComparing;
  final void Function(String stId) onStationTap;
  final VoidCallback onCompare;
  final VoidCallback onClose;
  final void Function(bool highwayOnly)? onHighwayFilterChanged;

  const _StationSelectInlineSheet({
    required this.sheetScrollCtrl,
    required this.stations,
    required this.selectedAId,
    required this.selectedBId,
    required this.wonFmt,
    required this.isComparing,
    required this.onStationTap,
    required this.onCompare,
    required this.onClose,
    this.onHighwayFilterChanged,
  });

  @override
  State<_StationSelectInlineSheet> createState() => _StationSelectInlineSheetState();
}

class _StationSelectInlineSheetState extends State<_StationSelectInlineSheet> {
  final ScrollController _listCtrl = ScrollController();
  bool _highwayOnly = false;

  bool _isHighwayStation(Map<String, dynamic> st) {
    // 서버가 휴게소 여부·상하행 필터까지 반영한 목록만 내림 — 앱은 플래그만 사용
    return st['is_highway_rest_area'] == true;
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stations = _highwayOnly
        ? widget.stations.where((s) => _isHighwayStation(s)).toList()
        : widget.stations;
    final selectedAId = widget.selectedAId;
    final selectedBId = widget.selectedBId;
    final bothSelected = selectedAId != null && selectedBId != null;

    // 최저가 ID 찾기
    String? cheapestId;
    int? cheapestPrice;
    for (final st in stations) {
      final price = st['price_won_per_liter'] is num ? (st['price_won_per_liter'] as num).round() : null;
      if (price != null && (cheapestPrice == null || price < cheapestPrice)) {
        cheapestPrice = price;
        cheapestId = st['id']?.toString();
      }
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, -2)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 시트를 최대로 내렸을 때는 고정 영역을 축약해서 overflow를 방지한다.
            final compact = constraints.maxHeight < 300;
            return Column(
          children: [
            // ─ 드래그 핸들 영역 (SingleChildScrollView로 드래그 활성화) ─
            SingleChildScrollView(
              controller: widget.sheetScrollCtrl,
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 핸들바
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.local_gas_station_rounded, size: 18, color: _kCompareBlue),
                        const SizedBox(width: 8),
                        const Text('주유소 선택',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
                        const SizedBox(width: 6),
                        Text('(${stations.length}곳)',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onClose,
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFF666666)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 선택 안내
                  if (!bothSelected && !compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Row(
                        children: [
                          _SelectBadge(label: selectedAId != null ? 'A 선택됨' : 'A 미선택',
                              color: const Color(0xFFE8700A), filled: selectedAId != null),
                          const SizedBox(width: 6),
                          _SelectBadge(label: selectedBId != null ? 'B 선택됨' : 'B 미선택',
                              color: _kCompareBlue, filled: selectedBId != null),
                          const Spacer(),
                          Text('지도에서도 선택 가능',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  if (!compact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Row(
                        children: [
                          FilterChip(
                            selected: _highwayOnly,
                            onSelected: (v) {
                              setState(() => _highwayOnly = v);
                              widget.onHighwayFilterChanged?.call(v);
                            },
                            label: const Text('고속도로만', style: TextStyle(fontSize: 12)),
                            showCheckmark: false,
                            selectedColor: const Color(0xFFE7F0FF),
                            backgroundColor: const Color(0xFFF5F5F5),
                            side: BorderSide(
                              color: _highwayOnly ? const Color(0xFF1D6FE0) : const Color(0xFFE0E0E0),
                            ),
                            labelStyle: TextStyle(
                              color: _highwayOnly ? const Color(0xFF1D6FE0) : const Color(0xFF666666),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _highwayOnly ? '휴게소/고속도로 후보만 표시' : '전체 후보 표시',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                ],
              ),
            ),

            // ─ 주유소 목록 ─
            Expanded(
              child: stations.isEmpty
                  ? const Center(
                      child: Text(
                        '고속도로 후보가 없습니다.\n필터를 해제해 전체 후보를 확인하세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFF999999), height: 1.4),
                      ),
                    )
                  : ListView.builder(
                controller: _listCtrl,
                itemCount: stations.length,
                itemBuilder: (ctx, index) {
                  final st = stations[index];
                  final stId = st['id']?.toString() ?? '$index';
                  final name = (st['display_name']?.toString().trim().isNotEmpty == true)
                      ? st['display_name'].toString()
                      : (st['name']?.toString() ?? '주유소 ${index + 1}');
                  final addr = st['address']?.toString() ?? '';
                  final price = st['price_won_per_liter'] is num
                      ? (st['price_won_per_liter'] as num).round() : null;

                  final isA = selectedAId == stId;
                  final isB = selectedBId == stId;
                  final isCheapest = cheapestId == stId;

                  final badgeColor = isA
                      ? const Color(0xFFE8700A)
                      : (isB ? _kCompareBlue : const Color(0xFF9E9E9E));

                  return InkWell(
                    onTap: () => widget.onStationTap(stId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          // 번호/선택 뱃지
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: (isA || isB) ? badgeColor : const Color(0xFFF0F0F0),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                isA ? 'A' : (isB ? 'B' : '${index + 1}'),
                                style: TextStyle(
                                  color: (isA || isB) ? Colors.white : const Color(0xFF666666),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(name,
                                          style: TextStyle(
                                            fontWeight: isCheapest ? FontWeight.w700 : FontWeight.w600,
                                            fontSize: 14,
                                            color: const Color(0xFF1a1a1a),
                                          ),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (isCheapest) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _kCompareBlue,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('최저가',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (addr.isNotEmpty)
                                  Text(addr, style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 가격
                          if (price != null)
                            Text(
                              '${widget.wonFmt.format(price)}원',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCheapest ? FontWeight.w700 : FontWeight.w500,
                                color: isCheapest ? _kCompareBlue : const Color(0xFFAAAAAA),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ─ 비교 버튼 ─
            if (!compact)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: bothSelected && !widget.isComparing ? widget.onCompare : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kCompareBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kCompareBlue.withOpacity(0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: widget.isComparing
                          ? const SizedBox(height: 22, width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              bothSelected
                                  ? '선택한 2곳 비교 분석'
                                  : '주유소 2곳을 선택하세요 (${(selectedAId != null ? 1 : 0) + (selectedBId != null ? 1 : 0)}/2)',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
          },
        ),
      ),
    );
  }
}

class _SelectBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const _SelectBadge({required this.label, required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.12) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: filled ? color.withOpacity(0.5) : Colors.grey[300]!),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled ? color : Colors.grey[500])),
    );
  }
}

// ─── 경로 카드 ─────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final String? originName;
  final String? destName;
  final String? currentLocationAddress;
  final VoidCallback onTapOrigin;
  final VoidCallback onTapDest;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDest;

  const _RouteCard({
    required this.originName,
    required this.destName,
    required this.currentLocationAddress,
    required this.onTapOrigin,
    required this.onTapDest,
    required this.onClearOrigin,
    required this.onClearDest,
  });

  @override
  Widget build(BuildContext context) {
    final usingGps = originName == null;
    final originLabel = originName ?? currentLocationAddress ?? '현재 위치';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 도트 + 선 — 각 점이 해당 행 중앙에 정렬되도록 고정 높이
          // 각 행 34px + divider 1px = 69px 총
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),  // 34/2 - 10/2
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPrimary, width: 2.5),
                ),
              ),
              Container(width: 2, height: 25, color: const Color(0xFFEEEEEE)),
              Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _kDanger)),
              const SizedBox(height: 12),  // 34/2 - 10/2
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 출발지
                GestureDetector(
                  onTap: onTapOrigin,
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            originLabel,
                            style: TextStyle(
                              fontSize: 13,
                              // GPS 모드: 주소가 있으면 진하게, 없으면 흐리게
                              color: usingGps
                                  ? (currentLocationAddress != null
                                      ? const Color(0xFF444444)
                                      : const Color(0xFF888888))
                                  : const Color(0xFF1a1a1a),
                              fontWeight: usingGps ? FontWeight.w400 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!usingGps)
                          GestureDetector(
                            onTap: onClearOrigin,
                            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFCCCCCC)),
                          )
                        else
                          const Icon(Icons.edit_location_alt_outlined, size: 14, color: Color(0xFFCCCCCC)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
                // 목적지
                GestureDetector(
                  onTap: onTapDest,
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            destName ?? '목적지를 입력하세요',
                            style: TextStyle(
                              fontSize: 13,
                              color: destName != null ? const Color(0xFF1a1a1a) : const Color(0xFFBBBBBB),
                              fontWeight: destName != null ? FontWeight.w500 : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (destName != null)
                          GestureDetector(
                            onTap: onClearDest,
                            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFCCCCCC)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 위치 선택 시트 ───────────────────────────────────────────────────────────

class _LocationPickerSheet extends ConsumerStatefulWidget {
  final bool isOrigin;
  final String? currentLocationAddress;
  final List<String> searchHistory;
  final List<Map<String, dynamic>> searchHistoryItems;
  final VoidCallback onMyLocation;
  final VoidCallback onMapPick;
  final Function(Map<String, dynamic>) onSearchResult;

  const _LocationPickerSheet({
    required this.isOrigin,
    required this.currentLocationAddress,
    required this.searchHistory,
    required this.searchHistoryItems,
    required this.onMyLocation,
    required this.onMapPick,
    required this.onSearchResult,
  });

  @override
  ConsumerState<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _myLocationSelected = false; // "내위치" 클릭 후 상단 옵션 표시
  int _searchRequestSeq = 0;

  // 시트 내부에서 현재 위치 주소를 직접 로드
  String? _localCurrentAddress;
  bool _addressLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    // 칩 subtitle용 주소만 로드 — 검색창은 건드리지 않음
    final preloaded = widget.currentLocationAddress;
    if (preloaded != null && preloaded.isNotEmpty) {
      if (mounted) setState(() { _localCurrentAddress = preloaded; _addressLoading = false; });
      return;
    }
    try {
      final loc = await ref.read(locationProvider.future);
      if (loc == null || !mounted) { setState(() => _addressLoading = false); return; }
      final addr = await ApiService().reverseGeocode(loc.lat, loc.lng);
      if (mounted) setState(() { _localCurrentAddress = addr; _addressLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _isLoading = false; _myLocationSelected = false; });
      return;
    }
    final reqId = ++_searchRequestSeq;
    setState(() => _isLoading = true);
    try {
      // 지도 탭과 동일하게 "좌표 근처 우선 검색"을 사용
      final center = ref.read(mapCenterProvider);
      final loc = center == null ? await ref.read(locationProvider.future) : null;
      final lat = center?.lat ?? loc?.lat;
      final lng = center?.lng ?? loc?.lng;
      final results = await ApiService().searchPlaces(query.trim(), lat: lat, lng: lng);
      if (!mounted || reqId != _searchRequestSeq) return;
      setState(() { _results = results; _isLoading = false; });
    } catch (_) {
      if (!mounted || reqId != _searchRequestSeq) return;
      setState(() { _results = []; _isLoading = false; });
    }
  }

  // "내위치" 칩 클릭 → 현재 주소를 검색창에 채우고 검색 (이미 채워졌으면 GPS 바로 사용)
  void _onMyLocationChipTap() {
    final addr = _localCurrentAddress;
    if (addr != null && addr.isNotEmpty) {
      if (_searchController.text == addr && _myLocationSelected) {
        // 이미 현재 주소로 채워진 상태 → GPS 그대로 사용
        widget.onMyLocation();
        return;
      }
      _searchController.text = addr;
      setState(() { _myLocationSelected = true; });
      _onSearchChanged(addr);
      _searchFocus.requestFocus();
    } else {
      widget.onMyLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.isOrigin ? '출발지 설정' : '목적지 설정',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            // ① 검색 필드 (상단)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (v) {
                  if (_myLocationSelected) setState(() => _myLocationSelected = false);
                  _onSearchChanged(v);
                },
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.isOrigin ? '출발지 검색' : '목적지 검색',
                  hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF999999), size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // ② 내위치 / 지도에서 선택 (검색창 바로 아래)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ThinChip(
                      icon: Icons.my_location_rounded,
                      label: _addressLoading
                          ? '내위치 (확인 중...)'
                          : (_localCurrentAddress != null
                              ? '내위치 · $_localCurrentAddress'
                              : '내위치'),
                      color: _kPrimary,
                      onTap: _onMyLocationChipTap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThinChip(
                      icon: Icons.map_outlined,
                      label: '지도에서 선택',
                      color: const Color(0xFF378ADD),
                      onTap: widget.onMapPick,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 검색 결과
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
                  : _searchController.text.isEmpty && !_myLocationSelected
                      ? (widget.searchHistoryItems.isEmpty
                          ? const Center(
                              child: Text('장소명, 주소를 입력하세요',
                                  style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB))))
                          : ListView.separated(
                              itemCount: widget.searchHistoryItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                              itemBuilder: (_, i) {
                                final h = widget.searchHistoryItems[i];
                                final name = h['name']?.toString() ?? '';
                                final address = h['address']?.toString() ?? '';
                                return ListTile(
                                  leading: const Icon(Icons.history_rounded, color: Color(0xFF999999), size: 20),
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: address.isNotEmpty
                                      ? Text(
                                          address,
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  onTap: () => widget.onSearchResult(h),
                                );
                              },
                            ))
                      : _results.isEmpty && !_myLocationSelected
                          ? const Center(
                              child: Text('검색 결과가 없습니다',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF999999))))
                          : ListView.builder(
                          itemCount: _results.length + (_myLocationSelected ? 1 : 0),
                          itemBuilder: (_, i) {
                            // 내위치 클릭 후 상단에 "현재 위치 그대로 사용" 옵션
                            if (_myLocationSelected && i == 0) {
                              return Column(
                                children: [
                                  ListTile(
                                    leading: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        color: _kPrimaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.my_location_rounded,
                                          color: _kPrimary, size: 18),
                                    ),
                                    title: const Text('현재 위치 사용',
                                        style: TextStyle(fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: _kPrimary)),
                                    subtitle: widget.currentLocationAddress != null
                                        ? Text(widget.currentLocationAddress!,
                                            style: const TextStyle(
                                                fontSize: 12, color: Color(0xFF888888)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)
                                        : null,
                                    onTap: widget.onMyLocation,
                                  ),
                                  if (_results.isNotEmpty)
                                    const Divider(height: 1, indent: 56),
                                ],
                              );
                            }
                            final r = _results[i - (_myLocationSelected ? 1 : 0)];
                            return Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.place_outlined,
                                      color: _kPrimary, size: 20),
                                  title: Text(r['name']?.toString() ?? '',
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w500)),
                                  subtitle: (r['address']?.toString() ?? '').isNotEmpty
                                      ? Text(r['address'].toString(),
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF999999)))
                                      : null,
                                  onTap: () => widget.onSearchResult(r),
                                ),
                                if (i < _results.length - 1 + (_myLocationSelected ? 1 : 0))
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          },
                        ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 얇은 칩 (하단 내위치/지도에서선택용) ──────────────────────────────────────

class _ThinChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ThinChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 잔량 요약 카드 ────────────────────────────────────────────────────────────

class _LevelSummaryCard extends StatelessWidget {
  final double currentLevel;
  final String targetMode;
  final TextEditingController priceController;
  final TextEditingController literController;
  final NumberFormat wonFmt;
  final bool isEv;

  const _LevelSummaryCard({
    required this.currentLevel,
    required this.targetMode,
    required this.priceController,
    required this.literController,
    required this.wonFmt,
    this.isEv = false,
  });

  String get _targetLabel {
    if (isEv) return '잔량 편집';
    if (targetMode == 'FULL') return '가득 채우기';
    if (targetMode == 'PRICE') {
      final p = double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0;
      return '${wonFmt.format(p.round())}원';
    }
    final l = double.tryParse(literController.text.replaceAll(',', '.')) ?? 0;
    return '${l > 0 ? l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1) : '—'}L';
  }

  Color get _levelColor {
    if (currentLevel <= 20) return const Color(0xFFE24B4A);
    if (currentLevel <= 50) return const Color(0xFFEF9F27);
    return isEv ? const Color(0xFF1D6FE0) : _kPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEv ? const Color(0xFF1D6FE0).withOpacity(0.3) : const Color(0xFFEEEEEE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('${currentLevel.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _levelColor)),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(builder: (_, c) {
                  final fillW = c.maxWidth * (currentLevel / 100);
                  return Stack(children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                          color: const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 7, width: fillW,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isEv
                                ? [const Color(0xFF1D6FE0), const Color(0xFF34C8F5)]
                                : [const Color(0xFFE24B4A), const Color(0xFFEF9F27),
                                   const Color(0xFFFFD60A), const Color(0xFF34C759)],
                            stops: isEv ? [0.0, 1.0] : [0.0, 0.35, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_rounded, size: 14, color: Color(0xFFCCCCCC)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_targetLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF666666))),
        ],
      ),
    );
  }
}

// ─── 잔량/목표 편집 바텀 시트 ──────────────────────────────────────────────────

class _LevelEditSheet extends StatefulWidget {
  final double initialLevel;
  final String initialMode;
  final TextEditingController priceController;
  final TextEditingController literController;
  final void Function(double level, String mode) onSave;
  final bool isEv;

  const _LevelEditSheet({
    required this.initialLevel,
    required this.initialMode,
    required this.priceController,
    required this.literController,
    required this.onSave,
    this.isEv = false,
  });

  @override
  State<_LevelEditSheet> createState() => _LevelEditSheetState();
}

class _LevelEditSheetState extends State<_LevelEditSheet> {
  late double _level;
  late String _mode;
  bool _useDte = false;
  final _dteController = TextEditingController();
  String? _dteError;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _dteController.dispose();
    super.dispose();
  }

  Color get _thumbColor {
    if (_level <= 20) return const Color(0xFFE24B4A);
    if (_level <= 50) return const Color(0xFFEF9F27);
    return _kPrimary;
  }

  void _applyDte(String val) {
    final box = Hive.box(AppConstants.settingsBox);
    final tank = (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num).toDouble();
    final eff = (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num).toDouble();
    final dte = double.tryParse(val.replaceAll(',', '.'));
    if (dte == null || dte <= 0) {
      setState(() => _dteError = '올바른 거리를 입력해주세요');
      return;
    }
    final liters = dte / eff;
    final pct = (liters / tank * 100).clamp(0.0, 100.0);
    setState(() { _level = pct; _dteError = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('잔량 & 목표 설정',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1a1a1a))),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── 잔량 입력 모드 토글 ──
              Row(
                children: [
                  const Text('현재 잔량',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF999999))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() { _useDte = !_useDte; _dteError = null; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _useDte ? _kPrimary.withOpacity(0.1) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _useDte ? _kPrimary : const Color(0xFFDDDDDD)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed_rounded, size: 13,
                              color: _useDte ? _kPrimary : const Color(0xFF888888)),
                          const SizedBox(width: 4),
                          Text('주행가능거리 입력',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: _useDte ? _kPrimary : const Color(0xFF888888))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── DTE 입력 or % 슬라이더 ──
              if (_useDte) ...[
                TextField(
                  controller: _dteController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '계기판 주행가능거리 (km)',
                    hintText: '예: 120',
                    suffixText: 'km',
                    errorText: _dteError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: _applyDte,
                ),
                const SizedBox(height: 8),
                Text(
                  '→ 잔량 약 ${_level.toStringAsFixed(1)}%로 계산됨',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _thumbColor,
                          inactiveTrackColor: const Color(0xFFF0F0F0),
                          thumbColor: _thumbColor,
                          overlayColor: _thumbColor.withOpacity(0.12),
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: _level,
                          min: 0, max: 100, divisions: 100,
                          onChanged: (v) => setState(() => _level = v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${_level.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                              color: Color(0xFF1a1a1a))),
                    ),
                  ],
                ),
              ],
              if (!widget.isEv) ...[
              const SizedBox(height: 16),
              const Text('목표 주유',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF999999))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in [('FULL', '가득'), ('PRICE', '금액 지정'), ('LITER', '리터 지정')])
                    GestureDetector(
                      onTap: () => setState(() => _mode = entry.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _mode == entry.$1 ? _kPrimary : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(entry.$2,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500,
                              color: _mode == entry.$1 ? Colors.white : const Color(0xFF666666),
                            )),
                      ),
                    ),
                ],
              ),
              if (_mode == 'PRICE') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: widget.priceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '목표 금액 (원)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
              if (_mode == 'LITER') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: widget.literController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '목표 리터 (L)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
              ], // if (!widget.isEv)
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => widget.onSave(_level, _mode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 아래 꼬리 삼각형 페인터 ──────────────────────────────────────────────────
class _DownTrianglePainter extends CustomPainter {
  final Color color;
  const _DownTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DownTrianglePainter old) => old.color != color;
}

// ─── EV 사용자 선택 모드 — 충전소 상세 바텀시트 ────────────────────────────────
class _EvStationDetailSheet extends StatefulWidget {
  final Map<String, dynamic> station;
  final String stationId;
  final String chargerType;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  final String? destName;
  final VoidCallback onMapTap;

  const _EvStationDetailSheet({
    required this.station,
    required this.stationId,
    required this.chargerType,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destName,
    required this.onMapTap,
  });

  @override
  State<_EvStationDetailSheet> createState() => _EvStationDetailSheetState();
}

class _EvStationDetailSheetState extends State<_EvStationDetailSheet> {
  bool _alarmEnabled = false;
  bool _alarmLoading = false;

  static const _kGreen = Color(0xFF1D9E75);
  static const _kBlue = Color(0xFF1D6FE0);
  static const _kOrange = Color(0xFFE8700A);
  static const _kGrey = Color(0xFF888888);

  @override
  void initState() {
    super.initState();
    _alarmEnabled = AlertService().isEvAlarmSubscribed(widget.stationId);
  }

  Future<void> _toggleAlarm() async {
    if (_alarmLoading) return;
    final name = widget.station['name']?.toString() ?? '';
    setState(() => _alarmLoading = true);
    try {
      if (_alarmEnabled) {
        await AlertService().unsubscribeEvAlarm(widget.stationId);
        if (mounted) setState(() => _alarmEnabled = false);
      } else {
        final ids = AlertService().evAlarmStationIds;
        if (!ids.contains(widget.stationId) && ids.length >= AlertService.evAlarmMaxCount) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('충전소 현황 알림은 최대 3개까지 설정할 수 있어요')),
            );
          }
          return;
        }
        final ok = await AlertService().subscribeEvAlarm(stationId: widget.stationId, stationName: name);
        if (mounted) setState(() => _alarmEnabled = ok);
      }
    } finally {
      if (mounted) setState(() => _alarmLoading = false);
    }
  }

  Color get _accentColor => widget.chargerType == 'FAST' ? _kBlue : _kGreen;

  @override
  Widget build(BuildContext context) {
    final s = widget.station;
    final name = s['name']?.toString() ?? '-';
    final address = s['address']?.toString() ?? '';
    final operator = s['operator']?.toString() ?? '';
    final availCount = (s['available_count'] as num?)?.toInt() ?? 0;
    final totalCount = (s['total_count'] as num?)?.toInt() ?? 0;
    final chargingCount = (s['charging_count'] as num?)?.toInt() ?? 0;
    final unitPrice = (s['unit_price'] as num?)?.toInt();
    final detourMin = (s['detour_time_min'] as num?)?.toInt();
    final originDistM = (s['origin_distance_m'] as num?)?.toInt();
    final originEtaMin = (s['origin_eta_min'] as num?)?.toInt();
    final accentColor = _accentColor;

    String? originDistLabel;
    if (originDistM != null && originDistM > 0) {
      originDistLabel = originDistM >= 1000
          ? '출발지에서 ${(originDistM / 1000).toStringAsFixed(0)}km'
          : '출발지에서 ${originDistM}m';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          // 핸들
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                // ── 헤더 ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                          const SizedBox(height: 4),
                          if (operator.isNotEmpty)
                            Text(operator, style: const TextStyle(fontSize: 13, color: _kGrey)),
                          if (address.isNotEmpty)
                            Text(address, style: const TextStyle(fontSize: 12, color: _kGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 알림 토글
                    GestureDetector(
                      onTap: _alarmLoading ? null : _toggleAlarm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _alarmEnabled ? accentColor.withOpacity(0.12) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _alarmEnabled ? accentColor : Colors.transparent),
                        ),
                        child: _alarmLoading
                            ? SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _alarmEnabled ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                                    size: 15, color: _alarmEnabled ? accentColor : _kGrey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _alarmEnabled ? '알림 켜짐' : '상태 알림',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                      color: _alarmEnabled ? accentColor : _kGrey),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── 현황 요약 카드 ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _StatusBadge(label: '이용가능', count: availCount, color: _kGreen),
                      const SizedBox(width: 10),
                      _StatusBadge(label: '충전중', count: chargingCount, color: _kOrange),
                      const SizedBox(width: 10),
                      _StatusBadge(label: '총 대수', count: totalCount, color: _kGrey),
                      const Spacer(),
                      if (unitPrice != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${NumberFormat('#,###', 'ko_KR').format(unitPrice)}원',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accentColor)),
                            const Text('/kWh', style: TextStyle(fontSize: 10, color: _kGrey)),
                          ],
                        )
                      else
                        const Text('가격 미공개', style: TextStyle(fontSize: 12, color: _kGrey)),
                    ],
                  ),
                ),

                // ── 경로 정보 ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (originDistLabel != null)
                        _InfoTag(icon: Icons.near_me_rounded, label: originDistLabel, color: _kGrey),
                      if (originEtaMin != null && originEtaMin > 0)
                        _InfoTag(icon: Icons.schedule_rounded, label: '약 ${fmtMin(originEtaMin)} 소요', color: _kGrey),
                      if (detourMin != null && detourMin == 0)
                        _InfoTag(icon: Icons.check_circle_rounded, label: '경로 이탈 없음', color: _kGreen)
                      else if (detourMin != null && detourMin > 0)
                        _InfoTag(icon: Icons.u_turn_right_rounded, label: '+${fmtMin(detourMin)} 우회', color: _kOrange),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // ── 액션 버튼 (사용자 선택: 경유만 지도에 표시. AI 결과 모드로 전환하지 않음) ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onMapTap,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text('지도에서 경로 보기', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.destLat != null ? () async {
                          // 이미 활성 워치 세션이 있으면 전환 확인
                          final existingSession = WatchService().session;
                          if (existingSession != null && existingSession.statId != widget.stationId && context.mounted) {
                            final switchOk = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('자리 변동 알림 전환', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                content: Text(
                                  '\'${existingSession.stationName}\'의 알림이 진행 중이에요.\n현재 알림을 끄고 이 충전소로 전환할까요?',
                                  style: const TextStyle(fontSize: 13, height: 1.5),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('아니요', style: TextStyle(color: Color(0xFF888888))),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: Text('전환하기', style: TextStyle(color: accentColor, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            );
                            if (switchOk != true || !context.mounted) return;
                            await WatchService().stop();
                          }
                          // 워치 제안 다이얼로그 (시트 팝 전에 표시)
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => _WatchProposalDialog(
                              etaMin: originEtaMin,
                              accentColor: accentColor,
                            ),
                          );
                          if (accepted == true) {
                            WatchService().start(
                              statId: widget.stationId,
                              stationName: name,
                              etaMin: originEtaMin ?? 0,
                              currentAvail: availCount,
                            );
                          }
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          if (!context.mounted) return;
                          showViaWaypointNavigationSheet(
                            context,
                            originLat: widget.originLat,
                            originLng: widget.originLng,
                            waypointLat: (s['lat'] as num).toDouble(),
                            waypointLng: (s['lng'] as num).toDouble(),
                            waypointName: name,
                            destinationLat: widget.destLat!,
                            destinationLng: widget.destLng!,
                            destinationName: widget.destName ?? '목적지',
                          );
                        } : null,
                        icon: Icon(Icons.navigation_rounded, size: 16, color: accentColor),
                        label: Text('길안내', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => EvDetailScreen(stationId: widget.stationId),
                            ),
                          );
                        },
                        icon: Icon(Icons.info_outline_rounded, size: 16, color: accentColor),
                        label: Text('충전소 상세보기', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
      ],
    );
  }
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoTag({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ChargerRow extends StatelessWidget {
  final Charger charger;
  const _ChargerRow({required this.charger});

  static const _statusColors = {
    ChargerStatus.available: Color(0xFF1D9E75),
    ChargerStatus.charging:  Color(0xFFE8700A),
    ChargerStatus.commError:    Color(0xFF888888),
    ChargerStatus.suspended:    Color(0xFF888888),
    ChargerStatus.maintenance:  Color(0xFF888888),
    ChargerStatus.unknown:      Color(0xFF888888),
  };

  static const _statusLabels = {
    ChargerStatus.available: '이용가능',
    ChargerStatus.charging:  '충전중',
    ChargerStatus.commError:    '통신오류',
    ChargerStatus.suspended:    '중지',
    ChargerStatus.maintenance:  '점검중',
    ChargerStatus.unknown:      '상태미확인',
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[charger.status] ?? const Color(0xFF888888);
    final statusLabel = _statusLabels[charger.status] ?? '-';
    final speedLabel = charger.isUltraFast ? '초급속' : charger.isFast ? '급속' : '완속';
    final speedColor = charger.isFast ? const Color(0xFF1D6FE0) : const Color(0xFF1D9E75);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: speedColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(speedLabel,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: speedColor)),
          ),
          const SizedBox(width: 6),
          Text(charger.typeText,
            style: const TextStyle(fontSize: 12, color: Color(0xFF444444))),
          const SizedBox(width: 4),
          Text('${charger.output}kW',
            style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
          const Spacer(),
          Text(statusLabel,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ── 워치 제안 다이얼로그 ──────────────────────────────────────────────────────────
class _WatchProposalDialog extends StatelessWidget {
  final int? etaMin;
  final Color accentColor;

  const _WatchProposalDialog({required this.etaMin, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.radar_rounded, size: 32, color: accentColor),
            ),
            const SizedBox(height: 16),
            const Text(
              '실시간 현황 알림',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 10),
            Text(
              etaMin != null && etaMin! > 0
                  ? '약 ${fmtMin(etaMin!)} 소요 예정이에요.\n이동하는 동안 자리 변동 시\n알림을 드릴게요.'
                  : '이동하는 동안 자리 변동 시\n알림을 드릴게요.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.65),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      '나중에',
                      style: TextStyle(color: Color(0xFF888888), fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('받기', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
