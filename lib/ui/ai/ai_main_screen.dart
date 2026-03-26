import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
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

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadCurrentAddress();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _literController.dispose();
    _reverseGeocodeDebounce?.cancel();
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
      if (mounted) setState(() => _currentLocationAddress = addr);
    } catch (_) {}
  }

  // ── 지도 준비 → GPS 위치로 이동 ──
  void _onMapReady(NaverMapController controller) async {
    _mapController = controller;
    try {
      final loc = await ref.read(locationProvider.future);
      if (loc == null || !mounted) return;
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(loc.lat, loc.lng),
          zoom: 14,
        ),
      );
    } catch (_) {}
  }

  // ── 카메라 정지 → 피커 모드에서 역지오코딩 ──
  void _onCameraIdle() async {
    if (!_isPickerMode || _mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
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
    Future.delayed(const Duration(milliseconds: 300), _onCameraIdle);
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
      },
      'recommendation': {'top_n_candidates_returned': 5},
    };

    try {
      final data = await ApiService().postRefuelAnalyze(body);
      if (!mounted) return;
      final status = data['meta'] is Map ? (data['meta'] as Map)['status']?.toString() : null;
      if (status == 'ok') {
        final originLabel = _originName ?? '현재 위치';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AiResultScreen(
              data: data,
              destinationName: _destName ?? '목적지',
              routeSummary: '$originLabel → ${_destName ?? '목적지'}',
              originLat: _lastStartLat,
              originLng: _lastStartLng,
              pathPoints: _lastPathPoints,
            ),
          ),
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

    if (!settings.aiOnboardingDone) {
      if (TickerMode.of(context) && !_onboardingPushed) {
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

    return Scaffold(
      body: Stack(
        children: [
          // ── 배경 지도 ──
          NaverMapWidget(
            options: const NaverMapViewOptions(
              mapType: NMapType.basic,
              locationButtonEnable: false,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: _onMapReady,
            onCameraIdle: _onCameraIdle,
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
          if (!_isPickerMode)
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
          if (!_isPickerMode)
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
        ],
      ),
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
          // 도트 + 선
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPrimary, width: 2.5),
                ),
              ),
              Container(
                  width: 2, height: 26,
                  color: const Color(0xFFEEEEEE),
                  margin: const EdgeInsets.symmetric(vertical: 4)),
              Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _kDanger)),
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
                              color: usingGps ? const Color(0xFF888888) : const Color(0xFF1a1a1a),
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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() { _results = []; _isLoading = false; });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final loc = await ref.read(locationProvider.future);
        final results = await ApiService().searchPlaces(query, lat: loc?.lat, lng: loc?.lng);
        if (mounted) setState(() { _results = results; _isLoading = false; });
      } catch (_) {
        if (mounted) setState(() { _results = []; _isLoading = false; });
      }
    });
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                widget.isOrigin ? '출발지 설정' : '목적지 설정',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            // 내위치 / 지도에서 선택
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionChip(
                      icon: Icons.my_location_rounded,
                      label: '내위치',
                      subtitle: widget.currentLocationAddress,
                      color: _kPrimary,
                      onTap: widget.onMyLocation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionChip(
                      icon: Icons.map_rounded,
                      label: '지도에서 선택',
                      color: const Color(0xFF378ADD),
                      onTap: widget.onMapPick,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 검색 필드
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
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
            // 검색 결과
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
                  : _results.isEmpty && _searchController.text.isNotEmpty
                      ? const Center(
                          child: Text('검색 결과가 없습니다',
                              style: TextStyle(fontSize: 14, color: Color(0xFF999999))))
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 56),
                          itemBuilder: (_, i) {
                            final r = _results[i];
                            return ListTile(
                              leading: const Icon(Icons.place_outlined, color: _kPrimary, size: 20),
                              title: Text(r['name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              subtitle: (r['address']?.toString() ?? '').isNotEmpty
                                  ? Text(r['address'].toString(),
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF999999)))
                                  : null,
                              onTap: () => widget.onSearchResult(r),
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

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
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

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _mode = widget.initialMode;
  }

  Color get _thumbColor {
    if (_level <= 20) return const Color(0xFFE24B4A);
    if (_level <= 50) return const Color(0xFFEF9F27);
    return _kPrimary;
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
              const Text('현재 잔량',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF999999))),
              const SizedBox(height: 8),
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
