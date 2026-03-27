import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/location_service.dart';
import '../../providers/providers.dart';
import 'ai_onboarding_screen.dart';
import 'ai_result_screen.dart';
import 'ai_vehicle_setup_screen.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kDanger = Color(0xFFE24B4A);

class AiMainScreen extends ConsumerStatefulWidget {
  const AiMainScreen({super.key});

  @override
  ConsumerState<AiMainScreen> createState() => _AiMainScreenState();
}

class _AiMainScreenState extends ConsumerState<AiMainScreen> {
  // ── 지도 ──
  NaverMapController? _mapController;
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

  // ── 잔량/목표 ──
  double _currentLevelPercent = 25.0;
  String _targetMode = 'FULL';
  final _priceController = TextEditingController(text: '50000');
  final _literController = TextEditingController(text: '20');

  // ── 분석 상태 ──
  bool _analyzing = false;
  String? _errorMessage;
  bool _onboardingPushed = false;

  // ── 결과 지도 모드 ──
  bool _isResultMode = false;
  Map<String, dynamic>? _lastResultData;
  String? _lastRouteSummary;

  // ── 결과 패널 시트 크기 추적 ──
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _sheetSize = 0.45;

  // ── AI 추천 복원용 원본 파라미터 ──
  List<Map<String, dynamic>> _lastRecPathPoints = [];
  List<Map<String, dynamic>>? _lastRecSegments;
  double? _lastRecStLat, _lastRecStLng;
  String _lastRecStName = '';
  int? _lastRecStPrice;
  double? _lastRecSt2Lat, _lastRecSt2Lng;
  String _lastRecSt2Name = '';
  int? _lastRecSt2Price;
  List<dynamic>? _lastRecAlternatives;

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _sheetController.addListener(_onSheetChanged);
  }

  void _onSheetChanged() {
    if (mounted && _sheetController.isAttached) {
      setState(() => _sheetSize = _sheetController.size);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_addressLoaded) {
      _addressLoaded = true;
      _loadCurrentAddress();
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    _priceController.dispose();
    _literController.dispose();
    _reverseGeocodeDebounce?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  void _loadSaved() {
    final box = Hive.box(AppConstants.settingsBox);
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

  Future<void> _loadCurrentAddress() async {
    try {
      final loc = await ref.read(locationProvider.future);
      if (loc == null || !mounted) return;
      final addr = await ApiService().reverseGeocode(loc.lat, loc.lng);
      if (mounted) setState(() => _currentLocationAddress = addr ?? _currentLocationAddress);
    } catch (_) {}
  }

  // ── 지도 준비 → GPS 위치로 이동 + location overlay 표시 (지도탭과 동일) ──
  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
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
    } else {
      setState(() { _destLat = lat; _destLng = lng; _destName = name; });
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
        onMyLocation: () {
          Navigator.pop(ctx);
          if (isOrigin) {
            setState(() { _originLat = null; _originLng = null; _originName = null; });
          } else {
            ref.read(locationProvider.future).then((loc) {
              if (loc == null || !mounted) return;
              setState(() {
                _destLat = loc.lat;
                _destLng = loc.lng;
                _destName = _currentLocationAddress ?? '현재 위치';
              });
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
          if (isOrigin) {
            setState(() { _originLat = lat; _originLng = lng; _originName = name; });
          } else {
            setState(() { _destLat = lat; _destLng = lng; _destName = name; _errorMessage = null; });
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
      final loc = await ref.read(locationProvider.future);
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

    box.put(AppConstants.keyAiCurrentLevelPercent, _currentLevelPercent);
    box.put(AppConstants.keyAiTargetMode, _targetMode);
    if (_targetMode == 'PRICE') box.put(AppConstants.keyAiTargetValue, priceTarget);
    if (_targetMode == 'LITER') box.put(AppConstants.keyAiLiterTarget, literTarget);

    setState(() { _analyzing = true; _errorMessage = null; });

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
      final data = await ApiService().postRefuelAnalyze(body);
      if (!mounted) return;
      final status = data['meta'] is Map ? (data['meta'] as Map)['status']?.toString() : null;
      if (status == 'ok') {
        final originLabel = _originName ?? '현재 위치';
        final rec = data['recommendation'] is Map ? data['recommendation'] as Map<String, dynamic> : null;
        final choice = rec?['choice']?.toString() ?? 'on_route';
        final onRoute = data['on_route'] is Map ? data['on_route'] as Map<String, dynamic> : null;
        final bestDetour = data['best_detour'] is Map ? data['best_detour'] as Map<String, dynamic> : null;
        final onRouteSt = onRoute?['station'] is Map ? onRoute!['station'] as Map<String, dynamic> : null;
        final detourSt = bestDetour?['station'] is Map ? bestDetour!['station'] as Map<String, dynamic> : null;

        // 추천 주유소를 1번(주황), 다른 주유소를 2번(파랑)으로 표시
        final primarySt = choice == 'best_detour' ? detourSt : onRouteSt;
        final secondarySt = choice == 'best_detour' ? onRouteSt : detourSt;

        double? stLat, stLng, st2Lat, st2Lng;
        String stName = '추천 주유소', st2Name = '';
        int? stPrice, st2Price;
        if (primarySt != null) {
          stLat = primarySt['lat'] is num ? (primarySt['lat'] as num).toDouble() : null;
          stLng = primarySt['lng'] is num ? (primarySt['lng'] as num).toDouble() : null;
          stName = primarySt['name']?.toString() ?? '추천 주유소';
          final p = primarySt['price_won_per_liter'];
          stPrice = p is num ? p.round() : null;
        }
        if (secondarySt != null) {
          st2Lat = secondarySt['lat'] is num ? (secondarySt['lat'] as num).toDouble() : null;
          st2Lng = secondarySt['lng'] is num ? (secondarySt['lng'] as num).toDouble() : null;
          st2Name = secondarySt['name']?.toString() ?? '';
          final p2 = secondarySt['price_won_per_liter'];
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
            viaPathPoints = parsed;
            viaSegments = _parsePathSegments(primaryVia['path_segments']);
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
            viaPathPoints = parsed;
            viaSegments = _parsePathSegments(vpr['path_segments']);
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
          st2Lat: st2Lat,
          st2Lng: st2Lng,
          st2Name: st2Name,
          st2Price: st2Price,
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
      if (mounted) setState(() => _analyzing = false);
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
  void _drawResultOnMap({
    required List<Map<String, dynamic>> pathPoints,
    List<Map<String, dynamic>>? pathSegments, // 교통 구간 데이터
    required double originLat,
    required double originLng,
    required double? stLat,
    required double? stLng,
    required String stName,
    int? stPrice,
    double? st2Lat,
    double? st2Lng,
    String st2Name = '',
    int? st2Price,
    required double destLat,
    required double destLng,
    List<dynamic>? alternatives, // 대안 후보 (회색 마커)
  }) async {
    if (_mapController == null) return;

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

    // 추천 주유소 마커 (주황)
    if (stLat != null && stLng != null) {
      final stLabel = stPrice != null && stPrice > 0
          ? '${_wonFmt.format(stPrice)}원'
          : stName;
      final stMarker = NMarker(
        id: 'result_station',
        position: NLatLng(stLat, stLng),
        icon: await _resultMarkerIcon(stLabel, const Color(0xFFE8700A)),
        anchor: const NPoint(0.5, 1.0),
      );
      await _mapController!.addOverlay(stMarker);
    }

    // 대안 주유소 마커 (중간회색)
    if (st2Lat != null && st2Lng != null && st2Name.isNotEmpty) {
      final st2Label = st2Price != null && st2Price > 0
          ? '${_wonFmt.format(st2Price)}원'
          : st2Name;
      final st2Marker = NMarker(
        id: 'result_station2',
        position: NLatLng(st2Lat, st2Lng),
        icon: await _resultMarkerIcon(st2Label, const Color(0xFF757575)),
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
          final altMarker = NMarker(
            id: 'result_alt_$altIdx',
            position: NLatLng(altLat, altLng),
            icon: await _resultMarkerIcon(altLabel, const Color(0xFF9E9E9E)),
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

  // ── 다른 후보 경로보기 ──
  Future<void> _showAltRouteOnMap(Map<String, dynamic> altItem) async {
    if (_destLat == null || _destLng == null) return;
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
        pathPoints = parsed;
        pathSegments = _parsePathSegments(vrMap['path_segments']);
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
      st2Lat: _lastRecStLat,
      st2Lng: _lastRecStLng,
      st2Name: _lastRecStName,
      st2Price: _lastRecStPrice,
      destLat: _destLat!,
      destLng: _destLng!,
      alternatives: _lastRecAlternatives,
    );
  }

  Future<void> _clearResult() async {
    await _mapController?.clearOverlays(type: NOverlayType.pathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.multipartPathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.arrowheadPathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.marker);
    setState(() {
      _isResultMode = false;
      _lastResultData = null;
      _lastRouteSummary = null;
      _sheetSize = 0.45;
    });
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
      st2Lat: _lastRecSt2Lat,
      st2Lng: _lastRecSt2Lng,
      st2Name: _lastRecSt2Name,
      st2Price: _lastRecSt2Price,
      destLat: _destLat!,
      destLng: _destLng!,
      alternatives: _lastRecAlternatives,
    );
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

  void _showLevelEditSheet() {
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
        onSave: (level, mode) {
          setState(() { _currentLevelPercent = level; _targetMode = mode; });
          final box = Hive.box(AppConstants.settingsBox);
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

    // AI 탭(index 2)에 진입할 때마다 지도를 내 위치로 이동 + 주소 재로드
    ref.listen(bottomNavIndexProvider, (prev, next) {
      if (next == 2 && prev != 2) {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isResultMode) {
          _clearResult();
        } else {
          _showExitDialog();
        }
      },
      child: Scaffold(
      body: Stack(
        children: [
          // ── 배경 지도 ──
          NaverMap(
            options: const NaverMapViewOptions(
              mapType: NMapType.basic,
              locationButtonEnable: false,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: _onMapReady,
            onCameraIdle: _onCameraIdle,
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
          if (!_isPickerMode && !_isResultMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 타이틀 바
                      Row(
                        children: [
                          const Spacer(),
                          const Text('주유 분석',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a))),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const AiVehicleSetupScreen(isEdit: true))),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                              ),
                              child: const Icon(Icons.tune_rounded, color: Color(0xFF666666), size: 18),
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
          if (!_isPickerMode && !_isResultMode)
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
                              onTap: _showLevelEditSheet,
                              child: _LevelSummaryCard(
                                currentLevel: _currentLevelPercent,
                                targetMode: _targetMode,
                                priceController: _priceController,
                                literController: _literController,
                                wonFmt: _wonFmt,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const AiVehicleSetupScreen(isEdit: true))),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fuelLabel,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kPrimary)),
                                  const SizedBox(height: 2),
                                  Text('${efficiency.toStringAsFixed(1)}km/L',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
                                  Text('${tankCapacity.toStringAsFixed(0)}L',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 분석 시작 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _analyzing ? null : _runAnalyze,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _kPrimary.withOpacity(0.55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _analyzing
                              ? const SizedBox(height: 22, width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('경로 분석 시작',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 결과 모드: 상단 뒤로가기 + 경로 요약 ──
          if (_isResultMode)
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
          if (_isResultMode && _lastResultData != null)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.45,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.12, 0.45, 0.9],
              builder: (_, sc) => Container(
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
                child: AiResultBody(
                  data: _lastResultData!,
                  destinationName: _destName ?? '목적지',
                  originLat: _lastStartLat,
                  originLng: _lastStartLng,
                  scrollController: sc,
                  onAltRouteView: _showAltRouteOnMap,
                  onResetToAiRec: _resetToAiRec,
                ),
              ),
            ),

          // ── 현재위치 버튼 (결과 모드: 시트 위에 붙어 이동) ──
          if (_isResultMode)
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

          // ── 일반 모드: 현재위치 버튼 (우하단) ──
          if (!_isPickerMode && !_isResultMode)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 180,
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
        ],
      ),
      ), // Scaffold
    ); // PopScope
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
  final VoidCallback onMyLocation;
  final VoidCallback onMapPick;
  final Function(Map<String, dynamic>) onSearchResult;

  const _LocationPickerSheet({
    required this.isOrigin,
    required this.currentLocationAddress,
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
                      ? const Center(
                          child: Text('장소명, 주소를 입력하세요',
                              style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB))))
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

  const _LevelSummaryCard({
    required this.currentLevel,
    required this.targetMode,
    required this.priceController,
    required this.literController,
    required this.wonFmt,
  });

  String get _targetLabel {
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
    return _kPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE24B4A), Color(0xFFEF9F27),
                              Color(0xFFFFD60A), Color(0xFF34C759)],
                            stops: [0.0, 0.35, 0.65, 1.0],
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

  const _LevelEditSheet({
    required this.initialLevel,
    required this.initialMode,
    required this.priceController,
    required this.literController,
    required this.onSave,
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
