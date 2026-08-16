import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../core/rate_limit_message.dart';
import '../../core/app_dialog.dart';
import '../../core/navigation/app_route_observer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/app_toast.dart';
import '../../core/util/ai_consent.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/connected_service.dart';
import '../../data/services/exit_ad_service.dart';
import '../../data/services/user_sync_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/station_alias_service.dart';
import '../../data/services/location_service.dart';
import '../../providers/providers.dart';
import 'ai_onboarding_screen.dart';
import 'widgets/ai_painters.dart';
import 'widgets/ev_station_detail_sheet.dart';
import 'widgets/ev_operator_picker.dart';
import 'widgets/soc_condition_sheet.dart';
import 'widgets/hero_card.dart';
import 'widgets/level_edit_sheet.dart';
import 'widgets/location_picker_sheet.dart';
import 'widgets/mode_segment.dart';
import 'widgets/route_card.dart';
import '../favorites/place_map_pick_screen.dart';
import 'widgets/route_engine_sheet.dart';
import 'widgets/savings_reveal_overlay.dart';
import 'widgets/station_select_inline_sheet.dart';
import 'ai_result_screen.dart';
import 'ai_vehicle_list_screen.dart';
import 'ai_vehicle_setup_screen.dart';
import 'ev_result_screen.dart';
import '../detail/gas_detail_screen.dart';
import '../home/home_screen.dart' show floatingNavOverlayPx;
import '../widgets/gas_station_map_badge.dart';
import 'ai_constants.dart';
import '../../data/services/rating_prompt_service.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/utils/ev_brand.dart';

class AiMainScreen extends ConsumerStatefulWidget {
  const AiMainScreen({super.key});

  @override
  ConsumerState<AiMainScreen> createState() => _AiMainScreenState();
}

class _AiMainScreenState extends ConsumerState<AiMainScreen> with RouteAware {
  // ── 지도 ──
  NaverMapController? _mapController;
  bool _brandImagesCached = false;
  // 커넥티드 차량 — 차에서 현재 상태 불러오기 진행 여부 / 마지막 조회 시각.
  bool _fetchingFromCar = false;
  DateTime? _lastCarSyncAt;
  StreamSubscription<({double lat, double lng})>? _locationSub;
  bool _isLocating = false;
  bool _isAtMyLocation = false;
  bool _suppressCameraChange = false;
  bool _addressLoaded = false;

  // 마커 오탭 가드 — 핀치 첫 손가락이 마커에 닿아 탭으로 오인 → 지도 팅김 방지.
  // (지도 탭 map_screen 과 동일 로직 이식)
  DateTime? _lastGestureAt;
  bool get _gestureActive =>
      _lastGestureAt != null &&
      DateTime.now().difference(_lastGestureAt!) <
          const Duration(milliseconds: 220);

  /// 마커 탭을 잠깐 유예 후 실행 — 탭 직후 핀치로 이어졌으면 무시.
  Future<bool> _tapGuard() async {
    if (_gestureActive) return false;
    await Future.delayed(const Duration(milliseconds: 130));
    if (!mounted || _gestureActive) return false;
    return true;
  }

  // NaverMap(PlatformView) 캐시 — setState 가 잦아도 rebuild 안 돼 제스처/줌 안 끊김.
  // consumeSymbolTapEvents 가 _isSelectMode 에 따라 바뀌므로 그 값이 변할 때만 재생성.
  Widget? _cachedMap;
  bool? _cachedMapSelectMode;
  bool? _cachedMapIsDark;

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
  // 경유지 (최대 3개) — 경로 프리뷰/추천 모두 경유 반영 경로를 따라간다
  final List<Map<String, dynamic>> _vias = []; // {lat,lng,name}
  // 경로 카드 접힘 — 경유지 3곳이면 5행(≈220px)이라 지도가 너무 좁다(형 제보).
  // 경로가 계산되면 한 번 자동으로 접고, 그 뒤로는 사용자 조작만 따른다.
  bool _routeCardCollapsed = false;
  // 경로가 나오면 경로 카드·차량 카드를 함께 한 번 접는다. 사용자가 둘 중 하나라도
  // 직접 조작하면 이 세션에선 더 건드리지 않는다.
  bool _panelsAutoCollapsed = false;
  final List<NMarker> _viaMarkers = []; // 지도 '경유 N' 마커

  // ── 분석에 사용된 마지막 경로 (결과화면 지도용) ──
  double _lastStartLat = 0, _lastStartLng = 0;
  List<Map<String, dynamic>> _lastPathPoints = [];
  List<Map<String, dynamic>>? _lastPathSegments;

  // ── 경로 대안 선택 (추천 0 / 고속도로우선 4) ──
  List<Map<String, dynamic>>? _routeAlts; // 서버 /route/alternatives 의 routes
  String _selectedRouteKey = 'recommend'; // 기본 선택: 추천경로(0)

  // ── "AI 추천으로 이만큼 절약" 보상풍 오버레이 (결과 도착 순간 1회) ──
  int _savingsRevealSeq = 0; // 새 결과마다 증가 → 오버레이 재생성 키
  String? _revealCaption;
  String? _revealHeadline;

  String? _revealStationName;
  String? _revealStationSub;
  String? _stationSub; // 공유 카드용 부제 (브랜드 · 주소)

  /// 오피넷 유종 코드 → 한글 (카드에 B027 같은 내부 코드가 노출되면 안 된다)
  static String? _fuelLabelOf(dynamic code) {
    const map = {
      'B027': '휘발유',
      'B034': '고급휘발유',
      'D047': '경유',
      'K015': 'LPG',
      'C004': '등유',
    };
    return map[code?.toString()];
  }

  /// 널·빈 값을 빼고 ' · ' 로 잇는다. 전부 비면 null → 카드가 그 줄을 통째로 생략.
  static String? _joinMeta(List<dynamic> parts) {
    final out = parts
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    return out.isEmpty ? null : out.join(' · ');
  }

  IconData _revealStationIcon = Icons.local_gas_station_rounded;
  List<RevealFact> _revealFacts = const [];

  void _showReveal(
    String caption,
    String headline, {
    String? stationName,
    String? stationSub,
    IconData stationIcon = Icons.local_gas_station_rounded,
    List<RevealFact> facts = const [],
    String? verdict,
    int? myUnitWon,
    int? avgUnitWon,
  }) {
    setState(() {
      _savingsRevealSeq++;
      _revealCaption = caption;
      _revealHeadline = headline;
      _revealStationName = stationName;
      _revealStationSub = stationSub;
      _revealStationIcon = stationIcon;
      _revealFacts = facts;
      _revealVerdict = verdict;
      _revealMyUnitWon = myUnitWon;
      _revealAvgUnitWon = avgUnitWon;
    });
  }

  String? _revealVerdict;
  int? _revealMyUnitWon;
  int? _revealAvgUnitWon;

  /// 주유 추천 — 절약 포인트 + 추천 상세(주유소명/단가/예상비용/추가시간)를 카드로.
  /// ① 우회 실질 절감(비교 데이터) 있으면 "N분 더 걸리지만 / M원 절감!"
  /// ② 아니면 주변 후보 평균가 대비 이번 주유 절약액 "주변 평균 대비 / M원 절약!"
  /// ③ 계산 불가 시 "우회할 필요 없이 / 가는 길이 최적!"
  void _triggerSavingsReveal(Map<String, dynamic> data) {
    int i(dynamic v) => v is num ? v.round() : 0;
    double? d(dynamic v) => v is num ? v.toDouble() : null;
    final wonFmt = NumberFormat('#,###');

    final rec = data['recommendation'];
    final trace = rec is Map ? rec['decision_trace'] : null;
    final ca = (trace is Map && trace['cost_analysis'] is Map)
        ? trace['cost_analysis'] as Map
        : null;
    final caSavings = ca == null
        ? 0
        : (ca['net_benefit_won'] is num
            ? i(ca['net_benefit_won'])
            : i(ca['savings_won']));

    // 추천 아이템 공통 추출 (이름/가격/예상비용/우회시간)
    final choice = rec is Map ? rec['choice']?.toString() : null;
    final recItem =
        choice == 'best_detour' ? data['best_detour'] : data['on_route'];
    final recSt = recItem is Map ? recItem['station'] : null;
    String name = '';
    double? recPrice;
    _stationSub = null;
    if (recSt is Map) {
      final dn = recSt['display_name']?.toString().trim();
      final raw = (dn != null && dn.isNotEmpty)
          ? dn
          : (recSt['name']?.toString() ?? '');
      name =
          StationAliasService.resolveGas((recSt['id'] ?? '').toString(), raw);
      recPrice = d(recSt['price_won_per_liter']);
      // 공유 카드 부제 — 서버가 주는 것 중 있는 것만 ' · ' 로 잇는다.
      _stationSub = _joinMeta([
        _fuelLabelOf(recSt['fuel_type']),
        recSt['brand_name'],
        recSt['address'],
      ]);
    }
    final recCost = recItem is Map ? d(recItem['expected_cost_won']) : null;
    final detourMin = recItem is Map ? i(recItem['detour_time_min']) : 0;

    // 주변 후보 평균가 (추천 제외)
    final prices = <double>[];
    void addPrice(dynamic item) {
      if (item is! Map) return;
      final st = item['station'];
      final p = st is Map ? d(st['price_won_per_liter']) : null;
      if (p != null) prices.add(p);
    }

    addPrice(data['on_route']);
    addPrice(data['best_detour']);
    if (data['alternatives'] is List) {
      for (final a in data['alternatives'] as List) {
        addPrice(a);
      }
    }
    final others = prices.where((p) => p != recPrice).toList();
    final avgPrice =
        others.isEmpty ? null : others.reduce((a, b) => a + b) / others.length;

    // 공유 카드(영수증형)가 시안대로 채워지려면 항목이 다 있어야 한다.
    // 절약은 '-' 가 아니라 ▼ 로 표기 — 카드·오버레이 공통 규칙.
    final computedMap = data['computed'];
    final goalLiters =
        computedMap is Map ? d(computedMap['goal_liters']) : null;
    final routeDistM = recItem is Map ? d(recItem['detour_distance_m']) : null;
    final fuelLabel = _fuelLabelOf(recSt is Map ? recSt['fuel_type'] : null);

    final facts = <RevealFact>[
      if (fuelLabel != null) (label: '유종', value: fuelLabel),
      if (recPrice != null)
        (label: '리터당 단가', value: '${wonFmt.format(recPrice.round())}원/L'),
      if (recPrice != null && avgPrice != null && avgPrice > recPrice)
        (
          label: '주변 평균 대비',
          value: '▼${wonFmt.format((avgPrice - recPrice).round())}원/L'
        ),
      if (avgPrice != null)
        (label: '주변 평균가', value: '${wonFmt.format(avgPrice.round())}원/L'),
      if (goalLiters != null && goalLiters > 0)
        (label: '주유량', value: '${goalLiters.toStringAsFixed(1)}L'),
      if (routeDistM != null && routeDistM > 0)
        (
          label: '거리',
          value: '경로에서 ${(routeDistM / 1000).toStringAsFixed(1)}km'
        ),
      if (recCost != null && recCost > 0)
        (label: '예상 주유비', value: '${wonFmt.format(recCost.round())}원'),
      if (detourMin > 0) (label: '추가 시간', value: '+$detourMin분'),
    ];

    if (caSavings >= 1000) {
      final extraMin = i(ca!['detour_extra_min']);
      _showReveal(
        extraMin > 0 ? '$extraMin분 더 걸리지만' : '가는 길 그대로',
        '${SavingsRevealOverlay.won(caSavings)} 절감!',
        stationName: name,
        stationSub: _stationSub,
        stationIcon: Icons.local_gas_station_rounded,
        facts: facts,
        verdict: extraMin > 0 ? '+$extraMin분 우회해도 이득' : '우회 없이 가는 길이 최적',
        myUnitWon: recPrice?.round(),
        avgUnitWon: avgPrice?.round(),
      );
      return;
    }

    final computed = data['computed'];
    final liters = computed is Map ? d(computed['goal_liters']) : null;
    final effLiters = liters ??
        ((recCost != null && recPrice != null && recPrice > 0)
            ? recCost / recPrice
            : null);
    if (recPrice != null &&
        avgPrice != null &&
        effLiters != null &&
        effLiters > 0) {
      final save = ((avgPrice - recPrice) * effLiters).round();
      if (save >= 500) {
        _showReveal(
          '주변 평균 대비',
          '${SavingsRevealOverlay.won(save)} 절약!',
          stationName: name,
          stationSub: _stationSub,
          stationIcon: Icons.local_gas_station_rounded,
          facts: facts,
          verdict: detourMin > 0 ? '+$detourMin분 우회해도 이득' : '우회 없이 가는 길이 최적',
          // 이 분기 조건에서 recPrice/avgPrice 는 non-null 로 승격됨
          myUnitWon: recPrice.round(),
          avgUnitWon: avgPrice.round(),
        );
        return;
      }
    }
    _showReveal(
      '우회할 필요 없이',
      '가는 길이 최적!',
      stationName: name,
      stationSub: _stationSub,
      stationIcon: Icons.local_gas_station_rounded,
      facts: facts,
      verdict: '우회 없이 가는 길이 최적',
      myUnitWon: recPrice?.round(),
      avgUnitWon: avgPrice?.round(),
    );
  }

  /// EV 추천 — 추천 충전소 예상요금 vs 다른 후보 평균 + 상세(요금/단가/충전량).
  void _triggerEvSavingsReveal(Map<String, dynamic> data) {
    final wonFmt = NumberFormat('#,###');
    int? cost(Map m) => m['est_cost_member'] is num
        ? (m['est_cost_member'] as num).round()
        : (m['est_cost'] is num ? (m['est_cost'] as num).round() : null);
    final rec = data['recommended'];
    final alts = data['alternatives'];
    String name = '';
    final facts = <RevealFact>[];
    int? recCost;
    int? unit; // 추천 단가 — 블록 밖(공유 카드 배선)에서도 쓴다
    _stationSub = null;
    if (rec is Map) {
      name = rec['name']?.toString() ?? '';
      final m = Map<String, dynamic>.from(rec);
      recCost = cost(m);
      _stationSub = _joinMeta([m['operator'], m['address']]);
      unit = m['unit_price_member'] is num
          ? (m['unit_price_member'] as num).round()
          : (m['unit_price'] is num ? (m['unit_price'] as num).round() : null);
      final kwh = m['est_charge_kwh'] is num
          ? (m['est_charge_kwh'] as num).toDouble()
          : null;
      if (recCost != null) {
        facts.add((label: '예상 충전요금', value: '${wonFmt.format(recCost)}원'));
      }
      if (unit != null) {
        facts.add((label: '단가', value: '${wonFmt.format(unit)}원/kWh'));
      }
      if (kwh != null && kwh > 0) {
        facts.add((label: '충전량', value: '${kwh.toStringAsFixed(1)}kWh'));
      }
    }
    // 주변 평균 단가 — 서버에 지역 평균 개념이 없어 '대안 후보 단가 평균' 으로 (시안 7e).
    int? avgUnit;
    if (alts is List) {
      final units = alts
          .whereType<Map>()
          .map((m) {
            final u = m['unit_price_member'] ?? m['unit_price'];
            return u is num ? u.round() : null;
          })
          .whereType<int>()
          .toList();
      if (units.isNotEmpty) {
        avgUnit = (units.reduce((a, b) => a + b) / units.length).round();
      }
    }
    final avail = rec is Map && rec['available_count'] is num
        ? (rec['available_count'] as num).round()
        : null;
    final evVerdict = (avail != null && avail > 0) ? '대기 없이 바로 충전 가능' : null;

    if (recCost != null && alts is List) {
      final altCosts = alts
          .whereType<Map>()
          .map((m) => cost(Map<String, dynamic>.from(m)))
          .whereType<int>()
          .toList();
      if (altCosts.isNotEmpty) {
        final avg = altCosts.reduce((a, b) => a + b) / altCosts.length;
        final save = (avg - recCost).round();
        if (save >= 500) {
          _showReveal(
            '다른 후보 평균 대비',
            '${SavingsRevealOverlay.won(save)} 절약!',
            stationName: name,
            stationSub: _stationSub,
            stationIcon: Icons.ev_station_rounded,
            facts: facts,
            verdict: evVerdict,
            myUnitWon: unit,
            avgUnitWon: avgUnit,
          );
          return;
        }
      }
    }
    _showReveal(
      '지금 배터리에 딱 맞는',
      '최적 충전소 추천!',
      stationName: name,
      stationSub: _stationSub,
      stationIcon: Icons.ev_station_rounded,
      facts: facts,
      verdict: evVerdict,
      myUnitWon: unit,
      avgUnitWon: avgUnit,
    );
  }

  bool _routesDistinct = false; // false면 두 경로 동일 → 선택 UI 숨김
  bool _loadingRouteAlts = false; // 경로 대안 불러오는 중 (로딩 표시)
  bool _heroCollapsed = false; // 배터리/차량 카드 접기 (지도 가림 최소화) // 교통 색상용

  // ── 잔량/목표 ──
  double _currentLevelPercent = 25.0;
  String _targetMode = 'FULL';
  final _priceController = TextEditingController(text: '50000');
  final _literController = TextEditingController(text: '20');

  // ── 분석 상태 ──
  bool _aiAnalyzing = false; // AI 분석 탭 로딩
  bool _userSelecting = false; // 사용자 선택 탭 로딩
  String _userSelectingMessage = '불러오는 중...';
  bool _isSelectSheetVisible = false;
  final DraggableScrollableController _selectSheetCtrl =
      DraggableScrollableController();
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

  /// AI 결과 화면에서 사용자가 다른 후보를 선택한 경우 그 stationId.
  /// _drawResultOnMap 가 alternative 마커 그릴 때 이 id 와 일치하면 보라색 강조.
  String? _selectedAltStationId;
  String? _selectedStationBId;
  bool _isCompareResultMode = false;
  bool _isEvResultMode = false;
  bool _isEvSelectMode = false;
  List<Map<String, dynamic>> _evSelectCandidates = [];
  // 직접선택 모드에서 kW 속도 필터가 완화됐는지 (선택 구간 충전소 0개 → 전체 급속)
  bool _evSelectSpeedRelaxed = false;
  // 직접선택 경로 보기 후 백버튼 복원용
  List<Map<String, dynamic>> _prevEvSelectCandidates = [];
  // EV 결과 화면에서 "지도에서 경로 보기" 중인지 (백버튼으로 결과 복원용)
  bool _isEvResultMapView = false;
  String _aiAnalysisType = 'gas'; // gas | ev
  String _evChargerType = 'FAST'; // FAST | SLOW
  // 고속도로 필터 — 형 확정: 디폴트 ON, 마지막 설정은 Hive 로 유지.
  static const _kEvHighwayKey = 'ai_highway_only_ev';
  static const _kGasHighwayKey = 'ai_highway_only_gas';
  // AI 탭 필터 마지막 사용값 유지 (형 확정 — 정렬 유지 제보와 같은 결)
  static const _kEvOperatorsKey = 'ai_ev_operators';
  static const _kEvBrandsKey = 'ai_ev_brands';
  static const _kEvChargerTypeKey = 'ai_ev_charger_type';
  static const _kEvFastOutputsKey = 'ai_ev_fast_outputs';
  static const _kGasPrefBrandsKey = 'ai_gas_pref_brands';
  // 잔량 조건 — 충전소 도착 하한 / 목적지 도착 하한. 서버 SoC 창의 ①③ 에 대응.
  static const _kEvMinArrivalSocKey = 'ai_ev_min_arrival_soc';
  static const _kEvDestMinSocKey = 'ai_ev_dest_min_soc';
  static const _kEvSocUserSetKey = 'ai_ev_soc_user_set';

  /// AI 탭 필터 상태를 Hive 에 저장 — 각 토글/시트 적용 지점에서 호출.
  void _saveAiFilters() {
    final box = Hive.box(AppConstants.settingsBox);
    box.put(_kEvOperatorsKey, _preferredEvOperators.toList());
    box.put(_kEvBrandsKey, _preferredEvBrands.toList());
    box.put(_kEvChargerTypeKey, _evChargerType);
    box.put(_kEvFastOutputsKey, _evFastOutputs.toList());
    box.put(_kGasPrefBrandsKey, _preferredGasBrands.toList());
    box.put(_kEvMinArrivalSocKey, _evMinArrivalSoc);
    box.put(_kEvDestMinSocKey, _evDestMinSoc);
    box.put(_kEvSocUserSetKey, _socConditionUserSet);
  }
  // 고속도로 전용 필터 — 기본 OFF. 켜진 채로 시내 경로를 돌리면 휴게소 후보 0개 →
  // 추천 불가/모순 화면이 나던 사고(2026-08-16). 고속도로 장거리 유저만 명시적으로 켠다.
  bool _evHighwayOnly = false; // 고속도로 충전소만
  bool _gasHighwayOnly = false; // 고속도로 휴게소 주유소만
  final Set<String> _preferredGasBrands =
      {}; // 선호 브랜드(OPINET pollDivCo 키). 빈 set = 전체.

  // EV 충전 사업자 필터 — 선택한 사업자 충전소만 추천. 빈 set = 전체.
  final Set<String> _preferredEvOperators = {};
  // AI 탭 자체 브랜드 충전소 선택 — 사업자 시트에 통합된 브랜드 섹션에서 고름
  // (지도·홈 필터의 brands 와 독립 — 형 확정: 지도 필터가 추천을 몰래 좁히지 않게)
  final Set<String> _preferredEvBrands = {};

  // EV 급속 kW 구간 필터('50'/'100'/'200'/'300') — 급속 모드에서만 의미. 빈 set = 전체.
  // 800V 차주의 "200kW+ 만" 니즈용. 서버가 후보 전멸 시 완화하고 speed_relaxed 로 알림.
  final Set<String> _evFastOutputs = {};
  static const _allFastOutputs = ['50', '100', '200', '300'];

  // 잔량 조건 — 사용자가 직접 적용하기 전까지는 요청에 안 싣는다. 서버 원격설정
  // (ev.min_arrival_soc / ev.dest_soc_safe)이 기본값이라 콘솔에서 무배포 튜닝이 가능한데,
  // 앱이 하드코딩 값을 매번 보내면 그 튜닝이 죽는다.
  // 대신 응답의 soc_conditions 로 표시값을 맞춰서 칩이 거짓말하지 않게 한다.
  int _evMinArrivalSoc = SocConditionSheet.defaultMinArrivalSoc;
  int _evDestMinSoc = SocConditionSheet.defaultDestMinSoc;
  bool _socConditionUserSet = false;

  bool get _socConditionCustom =>
      _socConditionUserSet &&
      (_evMinArrivalSoc != SocConditionSheet.defaultMinArrivalSoc ||
          _evDestMinSoc != SocConditionSheet.defaultDestMinSoc);

  // 반폭 타일에 들어가야 해서 최대한 압축 (가로 배치 — 형 지시)
  String get _socConditionSummary =>
      '도착 $_evMinArrivalSoc%·목적지 $_evDestMinSoc%';

  void _toggleEvFastOutput(String key) {
    setState(() {
      if (_evFastOutputs.isEmpty) {
        // 전체 선택 상태 → 해당 구간만 해제 (나머지 유지)
        _evFastOutputs.addAll(_allFastOutputs.where((k) => k != key));
      } else if (_evFastOutputs.contains(key)) {
        _evFastOutputs.remove(key); // 해제 (비면 전체로)
      } else {
        _evFastOutputs.add(key);
        // 전부 선택되면 전체(빈 set)로 정규화
        if (_allFastOutputs.every(_evFastOutputs.contains)) {
          _evFastOutputs.clear();
        }
      }
    });
    _saveAiFilters();
  }

  // EV 결과 시트의 카드 스크롤 제어용 (지도 마커 탭 → 해당 카드로 이동)
  final GlobalKey<EvResultBodyState> _evResultBodyKey =
      GlobalKey<EvResultBodyState>();

  // ── 검색 기록 ──
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _searchHistoryItems = [];

  // ── 마지막으로 동기화된 차량 ID (차량 전환 감지용) ──
  String? _lastSyncedVehicleId;

  // ── 결과 패널 시트 크기 추적 ──
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
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
  // 추천이 우회(st)인지 경로상(st2)인지 — 지도 마커 순위(1·2위) 결정용.
  bool _lastRecIsDetour = false;
  List<dynamic>? _lastRecAlternatives;

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _sheetController.addListener(_onSheetChanged);
    requestEvReplanNotifier.addListener(_onReplanRequested);
  }

  /// EV watch 만석 알림 "다른 충전소" 액션으로 재추천 신호 수신.
  /// 출발/목적지 컨텍스트가 살아있고 EV 차량 모드면 즉시 _runEvAnalyze 트리거.
  /// 컨텍스트 없거나 가스 모드면 사용자 입력 대기 (탭 전환만 발생).
  void _onReplanRequested() {
    if (!mounted) return;
    // 살짝 지연 후 트리거 — 탭 전환 애니메이션 끝나고 실행되도록
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final canReplan = _aiAnalysisType == 'ev' &&
          _destLat != null &&
          _destLng != null &&
          !_aiAnalyzing &&
          !_userSelecting;
      if (canReplan) _runEvAnalyze();
    });
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
    requestEvReplanNotifier.removeListener(_onReplanRequested);
    super.dispose();
  }

  // 선택된 차량 프로필 읽기
  VehicleProfile? _readSelectedVehicle(Box box) {
    final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    final rawVehicles = box.get(AppConstants.keyAiVehicles);
    if (rawVehicles == null) return null;
    try {
      final List decoded = jsonDecode(rawVehicles as String);
      final all = decoded
          .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      return all.cast<VehicleProfile?>().firstWhere((v) => v?.id == selectedId,
          orElse: () => all.isNotEmpty ? all.first : null);
    } catch (_) {
      return null;
    }
  }

  /// 상단 세그먼트 탭 → 모드 즉시 전환.
  /// 해당 모드 차량 보유 시 → 선택 차량을 그 모드 차량으로 교체.
  /// 없으면 → 차량 등록 페이지로 이동.
  Future<void> _switchModeTo({required bool ev}) async {
    final box = Hive.box(AppConstants.settingsBox);
    final rawVehicles = box.get(AppConstants.keyAiVehicles);
    List<VehicleProfile> all = [];
    if (rawVehicles != null) {
      try {
        final List decoded = jsonDecode(rawVehicles as String);
        all = decoded
            .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // 현재 선택 차량이 이미 그 모드면 noop
    final current = _readSelectedVehicle(box);
    if (current != null && current.isEV == ev) return;

    // 해당 모드 차량 찾기
    final candidate = all.cast<VehicleProfile?>().firstWhere(
          (v) => v != null && v.isEV == ev,
          orElse: () => null,
        );

    if (candidate != null) {
      // 차량 있음 → 즉시 전환
      await box.put(AppConstants.keyAiSelectedVehicleId, candidate.id);
      if (mounted) {
        setState(() {
          _aiAnalysisType = ev ? 'ev' : 'gas';
          _isResultMode = false;
          _isEvResultMode = false;
          _isEvSelectMode = false;
        });
        _loadSaved();
        // 주유↔충전 전환 시 경로 재조회 안 함 — 경로 지오메트리는 모드와 무관하고,
        // 칩은 시간·거리만 표시(개수 미사용)라 재조회가 순수 낭비였음(티맵 쿼터+UX 깜빡임).
        // 사용자가 고른 경로(추천/고속도로우선)도 그대로 유지됨.
      }
    } else {
      // 차량 없음 → 등록 페이지로 (충전분석이면 전기차로 시작)
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                AiVehicleSetupScreen(initialType: ev ? 'ev' : 'gas')),
      );
      if (mounted) setState(() {});
    }
  }

  // 차량 프로필 currentLevelPercent / targetMode / targetValue / targetChargePercent 저장
  void _saveVehicleLevel(Box box,
      {required double level,
      required String mode,
      double? price,
      double? targetChargePercent}) {
    final rawVehicles = box.get(AppConstants.keyAiVehicles);
    final selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    if (rawVehicles == null || selectedId == null) return;
    try {
      final List decoded = jsonDecode(rawVehicles as String);
      final all = decoded
          .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      final idx = all.indexWhere((v) => v.id == selectedId);
      if (idx < 0) return;
      all[idx] = all[idx].copyWith(
        currentLevelPercent: level,
        targetMode: mode,
        targetValue: price ?? all[idx].targetValue,
        targetChargePercent:
            targetChargePercent ?? all[idx].targetChargePercent,
      );
      box.put(AppConstants.keyAiVehicles,
          jsonEncode(all.map((v) => v.toJson()).toList()));
      mirrorAiVehiclesToServer(); // 로그인 회원이면 서버 미러
    } catch (_) {}
  }

  void _loadSaved() {
    final box = Hive.box(AppConstants.settingsBox);

    // 고속도로 필터 — 마지막 설정 복원 (없으면 OFF — 디폴트 ON이 시내 경로 추천을 깨던 사고)
    _evHighwayOnly = box.get(_kEvHighwayKey, defaultValue: false) == true;
    _gasHighwayOnly = box.get(_kGasHighwayKey, defaultValue: false) == true;

    // AI 탭 필터 — 마지막 사용값 복원 (없으면 기존 기본: 전체/급속)
    _preferredEvOperators
      ..clear()
      ..addAll(List<String>.from(
          box.get(_kEvOperatorsKey, defaultValue: const <String>[])));
    _preferredEvBrands
      ..clear()
      ..addAll(List<String>.from(
          box.get(_kEvBrandsKey, defaultValue: const <String>[])));
    _evChargerType =
        box.get(_kEvChargerTypeKey, defaultValue: 'FAST') == 'SLOW'
            ? 'SLOW'
            : 'FAST';
    _evFastOutputs
      ..clear()
      ..addAll(List<String>.from(
          box.get(_kEvFastOutputsKey, defaultValue: const <String>[])));
    _preferredGasBrands
      ..clear()
      ..addAll(List<String>.from(
          box.get(_kGasPrefBrandsKey, defaultValue: const <String>[])));
    _evMinArrivalSoc = (box.get(_kEvMinArrivalSocKey,
            defaultValue: SocConditionSheet.defaultMinArrivalSoc) as num)
        .round()
        .clamp(0, 50);
    _evDestMinSoc = (box.get(_kEvDestMinSocKey,
            defaultValue: SocConditionSheet.defaultDestMinSoc) as num)
        .round()
        .clamp(0, 50);
    _socConditionUserSet = box.get(_kEvSocUserSetKey, defaultValue: false) == true;

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
      _currentLevelPercent = (box.get(AppConstants.keyAiCurrentLevelPercent,
              defaultValue: 25.0) as num)
          .toDouble();
      _targetMode =
          box.get(AppConstants.keyAiTargetMode, defaultValue: 'FULL') as String;
      final price =
          (box.get(AppConstants.keyAiTargetValue, defaultValue: 50000.0) as num)
              .toDouble();
      _priceController.text = price.toStringAsFixed(0);
      final liter =
          (box.get(AppConstants.keyAiLiterTarget, defaultValue: 20.0) as num)
              .toDouble();
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

  // 목적지 경로 총 거리(km) — _lastPathPoints 합산. 목적지 미설정/경로없음이면 0.
  // hero card '도착 예상잔량' 계산용.
  double _destRouteDistanceKm() {
    if (_destLat == null || _destLng == null) return 0;
    final pts = _lastPathPoints;
    if (pts.length < 2) return 0;
    const rad = pi / 180;
    const earth = 6371000.0;
    double m = 0;
    for (int i = 1; i < pts.length; i++) {
      final aLat = (pts[i - 1]['lat'] as num?)?.toDouble();
      final aLng = (pts[i - 1]['lng'] as num?)?.toDouble();
      final bLat = (pts[i]['lat'] as num?)?.toDouble();
      final bLng = (pts[i]['lng'] as num?)?.toDouble();
      if (aLat == null || aLng == null || bLat == null || bLng == null) {
        continue;
      }
      final dLat = (bLat - aLat) * rad;
      final dLng = (bLng - aLng) * rad;
      final x = sin(dLat / 2) * sin(dLat / 2) +
          cos(aLat * rad) * cos(bLat * rad) * sin(dLng / 2) * sin(dLng / 2);
      m += 2 * earth * asin(min(1.0, sqrt(x)));
    }
    return m / 1000;
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
      _mapController
          ?.updateCamera(NCameraUpdate.withParams(target: target, zoom: 14));
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

  // ── 카메라 이동 중 ──
  void _onCameraChange(NCameraUpdateReason reason, bool animated) {
    if (reason == NCameraUpdateReason.gesture) _lastGestureAt = DateTime.now();
    if (_suppressCameraChange) return;
    if (!_isPickerMode) {
      // 일반 모드: 카메라 이동 시 내 위치 표시 해제
      if (_isAtMyLocation) setState(() => _isAtMyLocation = false);
      return;
    }
    // 피커 모드: 드래그 중 역지오코딩 준비 표시 (이미 표시 중이면 setState 스킵)
    if (!_isReverseGeocoding) setState(() => _isReverseGeocoding = true);
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce =
        Timer(const Duration(milliseconds: 500), () async {
      if (_mapController == null || !mounted) return;
      final camPos = await _mapController!.getCameraPosition();
      if (!mounted) return;
      setState(() => _pickerLatLng = camPos.target);
      final addr = await ApiService()
          .reverseGeocode(camPos.target.latitude, camPos.target.longitude);
      if (mounted) {
        setState(() {
          _pickerAddress = addr ?? '주소를 가져올 수 없습니다';
          _isReverseGeocoding = false;
        });
      }
    });
  }

  /// 배경 NaverMap — 한 번 생성 후 캐시. _isSelectMode / isDark 바뀔 때만 재생성.
  Widget _buildMap(bool isDark) {
    if (_cachedMapSelectMode != _isSelectMode || _cachedMapIsDark != isDark) {
      _cachedMap = null;
      _cachedMapSelectMode = _isSelectMode;
      _cachedMapIsDark = isDark;
    }
    return _cachedMap ??= NaverMap(
      options: NaverMapViewOptions(
        mapType: NMapType.basic,
        nightModeEnable: isDark,
        locationButtonEnable: false,
        consumeSymbolTapEvents: _isSelectMode,
        tiltGesturesEnable: false,
        // 대각선 핀치가 회전으로 인식돼 화면이 튀던 문제(형 재현: 3-9시 방향은 정상,
        // 대각선만 팅김) — 지도 탭·미니맵과 동일하게 회전도 끈다.
        rotationGesturesEnable: false,
      ),
      // forceHybridComposition 제거 → 기본 TLHC(텍스처) 경로. 과거 Flutter 3.24.3
      // 엔진 회귀(flutter#157463) 우회용이었으나 3.38.5 에서 해소. 강제 HC 가
      // 팬/줌 버벅임 주원인이라 제거 — 핀치 깨지면 true 로 롤백. (map_screen 과 동일)
      onMapReady: _onMapReady,
      onCameraIdle: _onCameraIdle,
      onSymbolTapped: _onSymbolTapped,
      onCameraChange: _onCameraChange,
    );
  }

  // ── 카메라 정지 → 피커 모드에서 역지오코딩 ──
  void _onCameraIdle() async {
    unawaited(_maybeSwapViaMarkerStyle()); // 경유 마커 줌 스타일 전환
    if (!_isPickerMode || _mapController == null || _suppressCameraChange)
      return;
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
    _reverseGeocodeDebounce =
        Timer(const Duration(milliseconds: 400), () async {
      final addr = await ApiService()
          .reverseGeocode(pos.target.latitude, pos.target.longitude);
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
      setState(() {
        _originLat = lat;
        _originLng = lng;
        _originName = name;
      });
      if (_destLat != null && _destLng != null) {
        unawaited(_loadRouteAlternatives());
      }
    } else {
      setState(() {
        _destLat = lat;
        _destLng = lng;
        _destName = name;
      });
      unawaited(_loadRouteAlternatives());
    }
    _exitPickerMode();
  }

  // ── 위치 선택 시트 ──
  void _showLocationSheet(
      {required bool isOrigin, bool forVia = false, int? viaIndex}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LocationPickerSheet(
        isOrigin: isOrigin,
        titleText: forVia ? '경유지 설정' : null,
        currentLocationAddress: _currentLocationAddress,
        searchHistory: _searchHistory,
        searchHistoryItems: _searchHistoryItems,
        onMyLocation: () {
          Navigator.pop(ctx);
          if (forVia) {
            // 경유지 = 현재 위치 (드물지만 흐름 통일)
            ref.read(locationProvider.future).then((loc) {
              if (loc == null || !mounted) return;
              _setVia(loc.lat, loc.lng, _currentLocationAddress ?? '현재 위치',
                  index: viaIndex);
            });
            return;
          }
          if (isOrigin) {
            setState(() {
              _originLat = null;
              _originLng = null;
              _originName = null;
            });
            unawaited(_loadCurrentAddress());
          } else {
            ref.read(locationProvider.future).then((baseLoc) async {
              final loc = baseLoc ??
                  await LocationService().getFreshPosition().then(
                        (p) => p == null
                            ? null
                            : (lat: p.latitude, lng: p.longitude),
                      );
              if (loc == null || !mounted) return;
              final resolved =
                  await ApiService().reverseGeocode(loc.lat, loc.lng);
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
              unawaited(_loadRouteAlternatives());
            });
          }
        },
        onMapPick: () {
          Navigator.pop(ctx);
          if (forVia) {
            // 경유지 지도 선택 — 즐겨찾기 지도선택 화면 재사용 (크로스헤어+현위치 버튼)
            Navigator.of(context)
                .push<Map<String, dynamic>>(MaterialPageRoute(
                    builder: (_) => const PlaceMapPickScreen(title: '경유지 선택')))
                .then((picked) {
              if (picked == null || !mounted) return;
              final lat = _asDouble(picked['lat']);
              final lng = _asDouble(picked['lng']);
              if (lat == null || lng == null) return;
              _setVia(lat, lng, (picked['name'] ?? '선택한 위치').toString(),
                  index: viaIndex);
            });
            return;
          }
          _enterPickerMode(isOrigin: isOrigin);
        },
        onSearchResult: (r) {
          Navigator.pop(ctx);
          final lat = _asDouble(r['lat']);
          final lng = _asDouble(r['lng']);
          final name = r['name']?.toString() ?? '';

          _saveSearchHistory(name, lat: lat, lng: lng);

          if (forVia) {
            if (lat != null && lng != null) {
              _setVia(lat, lng, name, index: viaIndex);
            }
            return;
          }
          if (isOrigin) {
            setState(() {
              _originLat = lat;
              _originLng = lng;
              _originName = name;
            });
            if (_destLat != null && _destLng != null) {
              unawaited(_loadRouteAlternatives());
            }
          } else {
            setState(() {
              _destLat = lat;
              _destLng = lng;
              _destName = name;
              _errorMessage = null;
            });
            unawaited(_loadRouteAlternatives());
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
        vias: _viaCoords,
        engine: RouteEnginePref.get(),
      );
      if (dr['success'] == true) {
        final parsed = _pathPointsFromServerJson(dr['path_points']);
        if (parsed != null) pathPoints = parsed;
        pathSegments = _segmentsFromPayload(dr);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ai-preview] getDrivingRoute 실패: $e');
    }

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;
    _lastPathSegments = pathSegments;
    _selectedAltStationId = null; // 새 경로 그릴 때 이전 선택 초기화

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

  // ── 경로 대안(추천 0 / 고속도로우선 4) ──────────────────────────────────
  List<Map<String, dynamic>>? _selectedRoutePoints() {
    final alts = _routeAlts;
    if (alts == null) return null;
    for (final r in alts) {
      if (r['key'] == _selectedRouteKey) {
        return _pathPointsFromServerJson(r['path_points']);
      }
    }
    return null;
  }

  int? _selectedRouteDurationMs() {
    final alts = _routeAlts;
    if (alts == null) return null;
    for (final r in alts) {
      if (r['key'] == _selectedRouteKey && r['duration_ms'] is num) {
        return (r['duration_ms'] as num).round();
      }
    }
    return null;
  }

  // 선택 경로의 교통색 세그먼트 (기존 경로와 동일하게 그리기 위함)
  List<Map<String, dynamic>>? _selectedRouteSegments() {
    final alts = _routeAlts;
    if (alts == null) return null;
    for (final r in alts) {
      if (r['key'] == _selectedRouteKey) {
        return _segmentsFromPayload(r);
      }
    }
    return null;
  }

  // 선택 안 된 대안 경로들의 폴리라인 (회색으로 같이 그리기 위함)
  List<List<Map<String, dynamic>>> _unselectedRoutesPoints() {
    final alts = _routeAlts;
    if (alts == null || !_routesDistinct) return [];
    final out = <List<Map<String, dynamic>>>[];
    for (final r in alts) {
      if (r['key'] != _selectedRouteKey) {
        final pts = _pathPointsFromServerJson(r['path_points']);
        if (pts != null && pts.length >= 2) out.add(pts);
      }
    }
    return out;
  }

  /// 목적지 설정 시 추천(0)+고속도로우선(4) 두 경로를 받아 칩으로 노출.
  /// 실패/빈 응답이면 기존 단일 미리보기로 폴백.
  Future<void> _loadRouteAlternatives() async {
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

    // 경로 기준 내비 — 최초 1회 선택 시트 (닫으면 이번엔 티맵, 다음 목적지 때 다시 물어봄)
    String? engine = RouteEnginePref.raw();
    if (engine == null && mounted) {
      engine = await showRouteEngineSheet(context) ?? 'tmap';
    }
    if (!mounted) return;
    // 새 경로를 다시 뽑는다 = 입력을 고치는 중 → 이번 결과가 나오면 다시 접어준다.
    // (이 리셋이 없으면 앱 실행 후 딱 한 번만 접히고, 목적지를 바꿔 넣을 때마다
    //  사용자가 매번 손으로 접어야 한다)
    setState(() {
      _loadingRouteAlts = true;
      _panelsAutoCollapsed = false;
    });
    try {
      final isEv = _aiAnalysisType == 'ev';
      final res = await ApiService().getRouteAlternatives(
        startLat: startLat,
        startLng: startLng,
        goalLat: _destLat!,
        goalLng: _destLng!,
        mode: isEv ? 'ev' : 'fuel',
        engine: engine,
        vias: _viaCoords,
      );
      final raw = res['routes'];
      final routes = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      if (routes.isEmpty) {
        setState(() {
          _routeAlts = null;
          _routesDistinct = false;
          _loadingRouteAlts = false;
        });
        unawaited(_showQuickRoutePreview());
        return;
      }
      setState(() {
        _routeAlts = routes;
        _routesDistinct = res['routes_distinct'] == true;
        _selectedRouteKey = 'recommend';
        _lastStartLat = startLat;
        _lastStartLng = startLng;
        _loadingRouteAlts = false;
        // 경로가 나왔다 = 입력이 끝났다 → 차량 카드(아래)는 접어 지도를 넓게 준다.
        // 상단 경로 카드는 형 확정: 출발·목적지만일 땐 접지 말고,
        // 경유지가 하나 이상일 때만 접는다 (경유지 추가하면 줄이 길어져서).
        // 한 번만 자동으로 접고, 사용자가 펼치면 다시 건드리지 않는다.
        if (!_panelsAutoCollapsed) {
          _panelsAutoCollapsed = true;
          _routeCardCollapsed = _viaCoords.isNotEmpty;
          _heroCollapsed = true; // 차량 카드(게이지·선호조건·브랜드)도 같이
        }
      });
      _applySelectedRoute();
    } catch (e) {
      if (kDebugMode) debugPrint('[route-alts] 실패: $e');
      if (!mounted) return;
      setState(() {
        _routeAlts = null;
        _routesDistinct = false;
        _loadingRouteAlts = false;
      });
      unawaited(_showQuickRoutePreview());
    }
  }

  void _selectRoute(String key) {
    if (key == _selectedRouteKey) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedRouteKey = key);
    _applySelectedRoute();
  }

  /// 출발지 ↔ 목적지 위치 바꾸기 (티맵 스타일). 출발지가 GPS면 현재 좌표로 확정 후 스왑.
  /// ⊕ — 네이버처럼 빈 '경유지 입력' 행부터 생성. 행을 탭하면 그때 검색 시트.
  void _addPendingVia() {
    if (_vias.length >= 3) return;
    HapticFeedback.selectionClick();
    setState(() => _vias.add({'lat': null, 'lng': null, 'name': ''}));
  }

  /// 경유지 추가/변경 — index null=추가(최대 3), 지정 시 그 슬롯 교체. 프리뷰/추천 재조회까지.
  void _setVia(double lat, double lng, String name, {int? index}) {
    HapticFeedback.selectionClick();
    setState(() {
      final entry = {'lat': lat, 'lng': lng, 'name': name};
      if (index != null && index >= 0 && index < _vias.length) {
        _vias[index] = entry;
      } else if (_vias.length < 3) {
        _vias.add(entry);
      }
    });
    _updateViaMarkers();
    if (_destLat != null && _destLng != null) {
      unawaited(_loadRouteAlternatives());
    }
  }

  void _removeVia(int index) {
    if (index < 0 || index >= _vias.length) return;
    setState(() => _vias.removeAt(index));
    _updateViaMarkers();
    if (_destLat != null && _destLng != null) {
      unawaited(_loadRouteAlternatives());
    }
  }

  /// 경유지 좌표 리스트 (API 전달용) — 아직 안 채운(pending) 행은 제외
  List<Map<String, dynamic>> get _viaCoords {
    final out = [
      for (final v in _vias)
        if (v['lat'] is num && v['lng'] is num)
          {'lat': v['lat'], 'lng': v['lng']},
    ];
    // 내비 호출(결과 화면·상세 시트)이 파라미터 없이도 같은 경유지를 쓰도록 세션에 반영
    AiRouteSession.set([
      for (final v in _vias)
        if (v['lat'] is num && v['lng'] is num)
          NavStop(
            name: (v['name'] ?? '경유지').toString().trim().isEmpty
                ? '경유지'
                : v['name'].toString(),
            lat: (v['lat'] as num).toDouble(),
            lng: (v['lng'] as num).toDouble(),
          ),
    ]);
    return out;
  }

  bool _viaMarkersBubble = false; // 확대 시 '경유 N' 버블 모드

  /// 지도 경유지 마커 전부 갱신 — 경로 redraw 가 marker 를 clear 하므로
  /// 각 draw 끝에서도 재호출된다. 축소=회색 원 번호, 확대=흰 '경유 N' 버블 (네이버식).
  Future<void> _updateViaMarkers() async {
    final c = _mapController;
    if (c == null || !mounted) return;
    for (final m in _viaMarkers) {
      try {
        await c.deleteOverlay(m.info);
      } catch (_) {}
    }
    _viaMarkers.clear();
    final bubble = _viaMarkersBubble;
    for (var i = 0; i < _vias.length; i++) {
      final v = _vias[i];
      if (v['lat'] is! num || v['lng'] is! num) continue; // pending 행
      try {
        final icon = await NOverlayImage.fromWidget(
          context: context,
          size: bubble ? const Size(64, 30) : const Size(22, 22),
          widget: bubble
              ? Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFD5DAE0)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2E000000),
                          blurRadius: 4,
                          offset: Offset(0, 1)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF8B95A1)),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 4),
                      const Text('경유',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: Color(0xFF334155))),
                    ],
                  ),
                )
              : Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B95A1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(0, 1)),
                    ],
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          color: Colors.white)),
                ),
        );
        final m = NMarker(
          id: 'ai_via_point_$i',
          position: NLatLng(
              (v['lat'] as num).toDouble(), (v['lng'] as num).toDouble()),
          icon: icon,
          size: bubble ? const Size(64, 30) : const Size(22, 22),
          anchor: const NPoint(0.5, 0.5),
        );
        await c.addOverlay(m);
        _viaMarkers.add(m);
      } catch (_) {}
    }
  }

  /// 줌 레벨에 따라 경유 마커 스타일 전환 (12.5 기준) — 카메라 idle 마다 체크.
  Future<void> _maybeSwapViaMarkerStyle() async {
    final c = _mapController;
    if (c == null || _vias.isEmpty) return;
    try {
      final pos = await c.getCameraPosition();
      final wantBubble = pos.zoom >= 12.5;
      if (wantBubble != _viaMarkersBubble) {
        _viaMarkersBubble = wantBubble;
        await _updateViaMarkers();
      }
    } catch (_) {}
  }

  /// (2+n)행 드래그 순서 변경 — GPS 출발지는 좌표 확정 후 이동.
  /// 행 인덱스: 0=출발, 1..n=경유, n+1=목적.
  Future<void> _reorderRouteSlots(int oldIndex, int newIndex) async {
    double? oLat = _originLat;
    double? oLng = _originLng;
    String? oName = _originName;
    if (oLat == null || oLng == null) {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null || !mounted) return;
      oLat = loc.lat;
      oLng = loc.lng;
      oName = _currentLocationAddress ?? '현재 위치';
    }
    final slots = <Map<String, dynamic>?>[
      {'lat': oLat, 'lng': oLng, 'name': oName},
      ..._vias,
      {'lat': _destLat, 'lng': _destLng, 'name': _destName},
    ];
    if (oldIndex < 0 || oldIndex >= slots.length) return;
    final moved = slots.removeAt(oldIndex);
    slots.insert(newIndex.clamp(0, slots.length), moved);
    // 빈 경유지(입력 전)는 자리표시일 뿐이라 출발·목적 칸에 앉을 수 없다.
    // 그렇다고 팝업으로 막으면 사용자는 '왜 안 되지' 하고 멈춘다 — 빈 칸만 가운데로
    // 밀어서 실제 장소끼리 자리가 바뀌게 한다. 되돌리지도, 알리지도 않는다.
    if (slots.first?['lat'] == null || slots.last?['lat'] == null) {
      final filled = slots.where((e) => e?['lat'] != null).toList();
      final empty = slots.where((e) => e?['lat'] == null).toList();
      if (filled.length < 2) return; // 채워진 곳이 하나뿐이면 바꿀 게 없다
      slots
        ..clear()
        ..add(filled.first)
        ..addAll(filled.sublist(1, filled.length - 1))
        ..addAll(empty)
        ..add(filled.last);
    }
    HapticFeedback.selectionClick();
    setState(() {
      final first = slots.first!;
      final last = slots.last!;
      _originLat = first['lat'] as double?;
      _originLng = first['lng'] as double?;
      _originName = first['name'] as String?;
      _destLat = last['lat'] as double?;
      _destLng = last['lng'] as double?;
      _destName = last['name'] as String?;
      _vias
        ..clear()
        ..addAll(slots
            .sublist(1, slots.length - 1)
            .whereType<Map<String, dynamic>>());
      _errorMessage = null;
    });
    _updateViaMarkers();
    if (_destLat != null && _destLng != null) {
      unawaited(_loadRouteAlternatives());
    }
  }

  Future<void> _swapOriginDest() async {
    if (_destLat == null || _destLng == null) return;
    double? oLat = _originLat;
    double? oLng = _originLng;
    String? oName = _originName;
    if (oLat == null || oLng == null) {
      final baseLoc = await ref.read(locationProvider.future);
      final loc = baseLoc ??
          await LocationService().getFreshPosition().then(
                (p) => p == null ? null : (lat: p.latitude, lng: p.longitude),
              );
      if (loc == null || !mounted) return;
      oLat = loc.lat;
      oLng = loc.lng;
      oName = _currentLocationAddress ?? '현재 위치';
    }
    final dLat = _destLat;
    final dLng = _destLng;
    final dName = _destName;
    HapticFeedback.selectionClick();
    setState(() {
      _originLat = dLat;
      _originLng = dLng;
      _originName = dName;
      _destLat = oLat;
      _destLng = oLng;
      _destName = oName;
      _errorMessage = null;
    });
    unawaited(_loadRouteAlternatives());
  }

  /// 선택된 경로 폴리라인을 지도에 다시 그리고 _lastPathPoints 갱신(분석이 재사용).
  /// 대안 API는 교통 세그먼트를 안 주므로 단색 폴리라인으로 그린다.
  void _applySelectedRoute() {
    final pts = _selectedRoutePoints();
    if (pts == null || pts.length < 2 || _destLat == null || _destLng == null)
      return;
    final segs = _selectedRouteSegments();
    _lastPathPoints = pts;
    _lastPathSegments = segs;
    _selectedAltStationId = null;
    unawaited(_drawResultOnMap(
      pathPoints: pts,
      pathSegments: segs,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      stLat: null,
      stLng: null,
      stName: '',
      destLat: _destLat!,
      destLng: _destLng!,
      greyRoutes: _unselectedRoutesPoints(),
    ));
  }

  // 접기 손잡이 — 경로 카드(RouteCard._collapseHandle)와 같은 칩+화살표 모양.
  // 회색 막대는 방향을 알려주지 않고 배경에도 묻혀서, 두 카드 모두 칩으로 통일했다.
  // 화살표는 각 카드가 '접히는 방향'을 가리킨다: 하단 카드라 펼침=아래로 접기,
  // 접힘=위로 펼치기. (상단 경로 카드는 반대 방향)
  // 지도 위에 떠 있을 땐(접힘 상태) 카드 배경이 없어 회색 칩이 안 보이므로 흰 칩+그림자.
  Widget _buildHeroToggleHandle({bool onMap = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _heroCollapsed = !_heroCollapsed;
        _panelsAutoCollapsed = true;
      }),
      // 위/아래로 드래그해서 펼치기/접기
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 80) {
          setState(() {
            _heroCollapsed = true;
            _panelsAutoCollapsed = true;
          });
        } else if (v < -80) {
          setState(() {
            _heroCollapsed = false;
            _panelsAutoCollapsed = true;
          });
        }
      },
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.only(top: onMap ? 0 : 10, bottom: 8),
        child: Container(
          width: 46,
          height: 22,
          decoration: BoxDecoration(
            color: onMap
                ? (isDark ? AppColors.darkMapOverlay : Colors.white)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFF1F3F6)),
            borderRadius: BorderRadius.circular(11),
            boxShadow: onMap
                ? [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Icon(
            _heroCollapsed
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 19,
            color:
                isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // 접힌 상태 요약 바 (차량 · 잔량 · 도달거리). 탭하면 펼침.
  Widget _buildCollapsedHeroBar({
    required bool isEv,
    required double level,
    required String vehicleName,
    required double reachableKm,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isEv ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
    final bg = isDark ? AppColors.darkMapOverlay : Colors.white;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.darkTextMuted : const Color(0xFF64748B);
    return GestureDetector(
      onTap: () => setState(() {
        _heroCollapsed = false;
        _panelsAutoCollapsed = true;
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: AppColors.darkCardBorder, width: 0.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
                isEv
                    ? Icons.ev_station_rounded
                    : Icons.local_gas_station_rounded,
                size: 18,
                color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(vehicleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
            ),
            const SizedBox(width: 8),
            Text('${level.round()}%',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
            const Spacer(),
            Text('~${reachableKm.round()}km',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: muted),
          ],
        ),
      ),
    );
  }

  // 충전 사업자 선택 바텀시트 — 상단 검색 + 대표 칩 + 검색 결과. 복수 선택, 미선택=전체.
  Future<void> _openEvOperatorSheet() async {
    final result = await showEvOperatorPicker(
      context,
      initial: Set<String>.from(_preferredEvOperators),
      initialBrands: Set<String>.from(_preferredEvBrands),
    );
    if (result == null) return; // 취소
    setState(() {
      _preferredEvOperators
        ..clear()
        ..addAll(result.operators);
      _preferredEvBrands
        ..clear()
        ..addAll(result.brands);
    });
    _saveAiFilters();
  }

  /// 잔량 조건 시트 — 충전소/목적지 도착 시 최소 잔량. 적용 시 바로 저장한다.
  Future<void> _openSocConditionSheet() async {
    final vehicle = _readSelectedVehicle(Hive.box(AppConstants.settingsBox));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkCard
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SocConditionSheet(
        initialMinArrivalSoc: _evMinArrivalSoc,
        initialDestMinSoc: _evDestMinSoc,
        // % ↔ km 병기용. 차량 미선택이면 0 이 되어 km 표기만 빠진다.
        capacity: vehicle?.batteryCapacity ?? 0,
        efficiency: vehicle?.evEfficiency ?? 0,
        onSave: (minArrival, destMin) {
          setState(() {
            _evMinArrivalSoc = minArrival;
            _evDestMinSoc = destMin;
            // 기본값 그대로 적용했으면 '서버 추종' 으로 되돌린다.
            // 무조건 true 로 두면, 시트를 한 번 열어보고 기본값으로 되돌린 사용자까지
            // 앱 하드코딩 15/20 에 영구히 고정돼 원격설정 튜닝이 죽는다(복귀 경로 없음).
            _socConditionUserSet =
                minArrival != SocConditionSheet.defaultMinArrivalSoc ||
                    destMin != SocConditionSheet.defaultDestMinSoc;
          });
          _saveAiFilters();
        },
      ),
    );
  }

  Widget _buildRouteSelector({required bool isEv}) {
    final accent = isEv ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
    // 경로 불러오는 중 — "왜 안 그려지지" 혼란 방지용 로딩 표시
    if (_loadingRouteAlts) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
              const SizedBox(width: 10),
              const Text('경로 비교 중…',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B))),
            ],
          ),
        ),
      );
    }
    final alts = _routeAlts;
    if (alts == null || alts.isEmpty) return const SizedBox.shrink();
    // 경로가 사실상 같아도 두 카드 모두 표시 (형 지시 — 하나만 보이면 헷갈림)
    final visible = alts;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 엔진 헤더 + 경로 칩을 한 카드로 묶음 (배지 따로 떠다니지 않게)
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _engineBadge(),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _routeChip(visible[i], isEv)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 경로 카드 헤더 — 현재 기준 내비 + 변경(▾). 탭하면 시트, 변경 시 재조회.
  Widget _engineBadge() {
    final label = RouteEnginePref.label(RouteEnginePref.get());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final prev = RouteEnginePref.get();
        final picked = await showRouteEngineSheet(context);
        if (picked != null && picked != prev && mounted) {
          setState(() {});
          unawaited(_loadRouteAlternatives());
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.alt_route_rounded,
                size: 14, color: Color(0xFF3B82F6)),
            const SizedBox(width: 5),
            Text('$label 기준',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155))),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: Color(0xFF64748B)),
            const Spacer(),
            const Text('변경',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  Widget _routeChip(Map<String, dynamic> r, bool isEv,
      {bool sameRoute = false}) {
    final accent = isEv ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
    final accentLight =
        isEv ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF);
    final selected = r['key'] == _selectedRouteKey;
    final label = (r['label'] ?? '경로').toString();
    final totalMin = ((r['duration_ms'] ?? 0) as num) ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final timeStr = h > 0 ? '$h시간 $m분' : '$m분';
    final km = (((r['distance_m'] ?? 0) as num) / 1000).round();
    final ink = selected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8);
    return GestureDetector(
      onTap: () => _selectRoute((r['key'] ?? 'recommend').toString()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accentLight : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? accent : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.check_circle_rounded, size: 14, color: accent),
                ],
                if (sameRoute) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('동일 경로',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8))),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14,
                    color: selected ? accent : const Color(0xFFB0BAC9)),
                const SizedBox(width: 4),
                Flexible(child: Text('$timeStr · ${km}km',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),)
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 분석 실행 ──
  Future<void> _runAnalyze() async {
    // 서드파티 AI 문구 동의 (첫 사용 1회 고지) — 거부해도 추천은 동일, 문구만 규칙 기반
    final aiOk = await AiConsent.ensure(context);
    if (!mounted) return;
    final box = Hive.box(AppConstants.settingsBox);
    // 선택 차량 프로필 = 단일 소스. 글로벌 키는 차량 없을 때만 fallback.
    final sv = _readSelectedVehicle(box);
    final fuelCode = sv?.fuelType ??
        (box.get(AppConstants.keyAiFuelType,
            defaultValue: FuelType.gasoline.code) as String);
    final tankCapacity = sv == null
        ? (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
            .toDouble()
        : (sv.isEV ? sv.batteryCapacity : sv.tankCapacity);
    final efficiency = sv == null
        ? (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
            .toDouble()
        : (sv.isEV ? sv.evEfficiency : sv.efficiency);

    if (_destLat == null || _destLng == null) {
      showAppToast(context, '목적지를 선택해 주세요.');
      return;
    }

    if (_targetMode == 'PRICE') {
      final p =
          double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
      if (p <= 0) {
        setState(() => _errorMessage = '목표 금액을 올바르게 입력해주세요.');
        return;
      }
    }
    if (_targetMode == 'LITER') {
      final l =
          double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0;
      if (l <= 0) {
        setState(() => _errorMessage = '목표 리터를 올바르게 입력해주세요.');
        return;
      }
    }

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) {
        if (!mounted) return;
        showAppToast(context, '현재 위치를 가져올 수 없습니다.', isError: true);
        return;
      }
      startLat = loc.lat;
      startLng = loc.lng;
    }

    final priceTarget = _targetMode == 'PRICE'
        ? (double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0)
        : 0.0;
    final literTarget = _targetMode == 'LITER'
        ? (double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0.0)
        : 0.0;
    final apiTargetValue = _targetMode == 'PRICE'
        ? priceTarget
        : (_targetMode == 'LITER' ? literTarget : 0.0);

    _saveVehicleLevel(box,
        level: _currentLevelPercent,
        mode: _targetMode,
        price: _targetMode == 'PRICE'
            ? priceTarget
            : (_targetMode == 'LITER' ? literTarget : null));
    // 글로벌 fallback
    box.put(AppConstants.keyAiCurrentLevelPercent, _currentLevelPercent);
    box.put(AppConstants.keyAiTargetMode, _targetMode);
    if (_targetMode == 'PRICE')
      box.put(AppConstants.keyAiTargetValue, priceTarget);
    if (_targetMode == 'LITER')
      box.put(AppConstants.keyAiLiterTarget, literTarget);

    setState(() {
      _aiAnalyzing = true;
      _errorMessage = null;
    });

    var pathPoints = <Map<String, dynamic>>[
      {'lat': startLat, 'lng': startLng},
      {'lat': _destLat!, 'lng': _destLng!},
    ];
    int? directDurationMs;

    // 사용자가 고른 경로(추천/고속도로우선)가 있으면 그 폴리라인을 그대로 분석에 쓴다.
    final selPts = _selectedRoutePoints();
    if (selPts != null && selPts.length >= 2) {
      pathPoints = selPts;
      directDurationMs = _selectedRouteDurationMs();
    } else {
      try {
        final dr = await ApiService().getDrivingRoute(
          startLat: startLat,
          startLng: startLng,
          goalLat: _destLat!,
          goalLng: _destLng!,
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
                final lat = e['lat'];
                final lng = e['lng'];
                if (lat is num && lng is num) {
                  parsed.add({'lat': lat.toDouble(), 'lng': lng.toDouble()});
                }
              }
            }
            if (parsed.length >= 2) pathPoints = parsed;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ai-analyze] getDrivingRoute 실패: $e');
      }
    }

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;

    final requestId =
        '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999999)}';
    final body = <String, dynamic>{
      'request_id': requestId,
      'ai_text': aiOk, // 서드파티 AI 문구 동의 — false 면 서버가 Gemini 스킵
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
        'engine': RouteEnginePref.get(), // 결과 지도 경유 경로를 같은 엔진으로
        'path_points': pathPoints,
        if (directDurationMs != null) 'duration_ms': directDurationMs,
        // 우회시간을 '경유지 포함 경로' 기준으로 재게 한다. 안 보내면 서버가
        // 경유지 없는 길을 기준으로 삼아 우회 10분을 0분으로 계산한다.
        if (_viaCoords.isNotEmpty) 'vias': _viaCoords,
        // 서버가 우회시간을 '내가 화면에서 본 경로'와 같은 엔진·같은 옵션으로 재게 한다.
        'route_key': _selectedRouteKey,
        'highway_only': _gasHighwayOnly,
        if (_preferredGasBrands.isNotEmpty)
          'preferred_brands': _preferredGasBrands
              .expand((k) => k == 'RTO' ? const ['RTO', 'RTX'] : [k])
              .toList(),
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
          if (err is Map && err['message'] != null)
            msg = err['message'].toString();
        }
        final isPrimaryInitError =
            msg.toLowerCase().contains('primary station') &&
                msg.toLowerCase().contains('before initialization');
        if (!isPrimaryInitError) rethrow;

        // 서버 특정 케이스 회피: recommendation 필드를 제거해 1회 재시도
        final retryBody = Map<String, dynamic>.from(body)
          ..remove('recommendation');
        data = await ApiService().postRefuelAnalyze(retryBody);
      }
      if (!mounted) return;
      final status = data['meta'] is Map
          ? (data['meta'] as Map)['status']?.toString()
          : null;
      if (status == 'ok') {
        // 통합 랭킹(ranked 1·2위) 있으면 기존 on_route/best_detour 슬롯에 치환 —
        // 렌더·지도 배선 그대로 재사용. 구서버 응답(ranked 없음)은 원본 유지.
        data = _applyRankedFrame(data);
        final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';
        final rec = data['recommendation'] is Map
            ? data['recommendation'] as Map<String, dynamic>
            : null;
        final choice = rec?['choice']?.toString() ?? 'on_route';
        final onRoute = data['on_route'] is Map
            ? data['on_route'] as Map<String, dynamic>
            : null;
        final bestDetour = data['best_detour'] is Map
            ? data['best_detour'] as Map<String, dynamic>
            : null;
        final onRouteSt = onRoute?['station'] is Map
            ? onRoute!['station'] as Map<String, dynamic>
            : null;
        final detourSt = bestDetour?['station'] is Map
            ? bestDetour!['station'] as Map<String, dynamic>
            : null;

        // 지도 표시는 타입 기준으로 고정:
        // - 경로상 최저가(on_route) = 파랑
        // - 우회 최저가(best_detour) = 1·2순위 배지로 구분
        // 추천 여부는 색이 아니라 라벨(배지)로만 표시
        final isRecDetour = choice == 'best_detour';

        double? stLat, stLng, st2Lat, st2Lng;
        String stName = '우회 최저가', st2Name = '경로상 최저가';
        int? stPrice, st2Price;

        // st = 우회 최저가 (분석 UI·지도 모두 파랑 #1D6FE0)
        if (detourSt != null) {
          stLat = detourSt['lat'] is num
              ? (detourSt['lat'] as num).toDouble()
              : null;
          stLng = detourSt['lng'] is num
              ? (detourSt['lng'] as num).toDouble()
              : null;
          final rawName = detourSt['name']?.toString() ?? '우회 최저가';
          stName = isRecDetour ? '추천 · $rawName' : rawName;
          final p = detourSt['price_won_per_liter'];
          stPrice = p is num ? p.round() : null;
        }

        // st2 = 경로상 최저가 (순위 배지로 표시)
        if (onRouteSt != null) {
          st2Lat = onRouteSt['lat'] is num
              ? (onRouteSt['lat'] as num).toDouble()
              : null;
          st2Lng = onRouteSt['lng'] is num
              ? (onRouteSt['lng'] as num).toDouble()
              : null;
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
        _triggerSavingsReveal(data);

        // 추천 주유소 경유 경로: 서버에서 미리 받은 전체 길찾기 우선, 없으면 클라이언트 네이버 호출
        var viaPathPoints = _lastPathPoints;
        List<Map<String, dynamic>>? viaSegments;
        final nav = data['navigation'] is Map
            ? data['navigation'] as Map<String, dynamic>
            : null;
        final vpr = nav?['via_primary_route'] is Map
            ? nav!['via_primary_route'] as Map<String, dynamic>
            : null;
        final onRouteVia = onRoute?['via_route'] is Map
            ? onRoute!['via_route'] as Map<String, dynamic>
            : null;
        final detourVia = bestDetour?['via_route'] is Map
            ? bestDetour!['via_route'] as Map<String, dynamic>
            : null;
        final primaryVia = choice == 'best_detour' ? detourVia : onRouteVia;
        // primaryVia 와 짝이 맞는 추천 주유소 좌표 (suspicious 폴백·재길찾기에 쓰이는 waypoint).
        // st = detour, st2 = on_route 이므로 choice 에 따라 골라야 한다.
        final primaryStLat = choice == 'best_detour' ? stLat : st2Lat;
        final primaryStLng = choice == 'best_detour' ? stLng : st2Lng;
        var usedServerPrimaryRoute = false;
        // 1순위: 추천 카드 자체의 via_route (on_route/best_detour)
        if (primaryVia != null) {
          final parsed = _pathPointsFromServerJson(primaryVia['path_points']);
          if (parsed != null) {
            if (primaryStLat != null && primaryStLng != null) {
              await _maybeReplaceViaRouteFromClient(
                serverPts: parsed,
                serverSeg: _segmentsFromPayload(primaryVia),
                stLat: primaryStLat,
                stLng: primaryStLng,
                serverViaRoute: primaryVia,
                apply: (pts, seg) {
                  viaPathPoints = pts;
                  viaSegments = seg;
                },
              );
            } else {
              viaPathPoints = parsed;
              viaSegments = _segmentsFromPayload(primaryVia);
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
            if (primaryStLat != null && primaryStLng != null) {
              await _maybeReplaceViaRouteFromClient(
                serverPts: parsed,
                serverSeg: _segmentsFromPayload(vpr),
                stLat: primaryStLat,
                stLng: primaryStLng,
                serverViaRoute: vpr,
                apply: (pts, seg) {
                  viaPathPoints = pts;
                  viaSegments = seg;
                },
              );
            } else {
              viaPathPoints = parsed;
              viaSegments = _segmentsFromPayload(vpr);
            }
            usedServerPrimaryRoute = true;
            _debugSegmentStats(
              label: 'navigation.via_primary_route',
              pathSegments: viaSegments,
              pathPoints: viaPathPoints,
            );
          }
        }
        if (!usedServerPrimaryRoute &&
            primaryStLat != null &&
            primaryStLng != null) {
          try {
            final vr = await ApiService().getDrivingRoute(
              startLat: _lastStartLat,
              startLng: _lastStartLng,
              goalLat: _destLat!,
              goalLng: _destLng!,
              waypointLat: primaryStLat,
              waypointLng: primaryStLng,
              // 사용자가 넣은 경유지도 함께 — 안 넣으면 지도가 경유지를 건너뛰고 그려진다
              vias: _viaCoords,
              engine: RouteEnginePref.get(),
            );
            if (vr['success'] == true) {
              final parsed = _pathPointsFromServerJson(vr['path_points']);
              if (parsed != null) viaPathPoints = parsed;
              viaSegments = _segmentsFromPayload(vr);
              _debugSegmentStats(
                label: 'client.getDrivingRoute(fallback)',
                pathSegments: viaSegments,
                pathPoints: viaPathPoints,
              );
            }
          } catch (e) {
            if (kDebugMode)
              debugPrint(
                  '[ai-analyze] viaRoute fallback getDrivingRoute 실패: $e');
          }
        }

        // AI 추천 복원용 파라미터 저장
        final recAlts =
            data['alternatives'] is List ? data['alternatives'] as List : null;
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
        _lastRecIsDetour = isRecDetour; // 추천이 우회(st)면 st=1순위, 아니면 st2=1순위
        _lastRecAlternatives = recAlts;
        _selectedAltStationId = null; // 새 분석 결과 그릴 때 이전 선택 초기화

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
        debugPrint('[AI] 분석 응답 오류: $err');
        setState(() => _errorMessage = '서버와 통신이 원활하지 않아요. 잠시 후 다시 시도해주세요.');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      debugPrint('[AI] 분석 통신 오류: ${e.message} / ${e.response?.data}');
      final rl = rateLimitMessage(e, feature: 'AI 주유소 추천');
      if (rl != null) {
        showAppDialog<void>(context,
            icon: Icons.schedule_rounded,
            title: '오늘은 여기까지!',
            message: rl,
            primaryLabel: '확인');
      } else {
        setState(() => _errorMessage = '서버와 통신이 원활하지 않아요. 잠시 후 다시 시도해주세요.');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[AI] 분석 예외: $e');
      setState(() => _errorMessage = '서버와 통신이 원활하지 않아요. 잠시 후 다시 시도해주세요.');
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
            painter: DownTrianglePainter(color),
          ),
        ],
      ),
      size: Size(w, totalH),
      context: context,
    );
  }

  // ── 정체도(congestion) → 색상 변환 ──
  // 네이버 Directions5 congestion 코드 (0-indexed):
  // 0(원활)=초록, 1(서행)=노랑, 2(지체)=주황, 3(정체)=빨강
  static Color _congestionColor(int congestion) {
    switch (congestion) {
      case 0:
        return const Color(0xFF39C56D).withValues(alpha: 0.78); // 원활 (연초록)
      case 1:
        return const Color(0xFFFFD75A).withValues(alpha: 0.78); // 서행 (연노랑)
      case 2:
        return const Color(0xFFFFB25A).withValues(alpha: 0.78); // 지체 (연주황)
      case 3:
        return const Color(0xFFF27573).withValues(alpha: 0.78); // 정체 (연빨강)
      default:
        return kPrimary.withValues(alpha: 0.78); // 미확인 (앱 기본색)
    }
  }

  static double _haversineM(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLng = (lng2 - lng1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  }

  /// Chaikin 코너 커팅 — 꺾인 좌표열을 부드러운 곡선으로 다듬음
  /// iterations=2 이면 원본 대비 ~4배 포인트 생성, 과도한 증폭 방지를 위해 2 고정
  static List<NLatLng> _smoothPath(List<NLatLng> coords, {int iterations = 2}) {
    var pts = coords;
    for (int iter = 0; iter < iterations; iter++) {
      if (pts.length < 3) break;
      final smooth = <NLatLng>[pts.first];
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        smooth.add(NLatLng(
          a.latitude * 0.75 + b.latitude * 0.25,
          a.longitude * 0.75 + b.longitude * 0.25,
        ));
        smooth.add(NLatLng(
          a.latitude * 0.25 + b.latitude * 0.75,
          a.longitude * 0.25 + b.longitude * 0.75,
        ));
      }
      smooth.add(pts.last);
      pts = smooth;
    }
    return pts;
  }

  /// 경로 점 간격이 큰 구간을 선형 보간으로 촘촘히 채워 표시를 부드럽게 한다.
  /// (좌표 자체를 바꾸는 게 아니라, 지도 렌더용 좌표만 보간)
  static List<NLatLng> _densifyPath(
    List<NLatLng> coords, {
    double maxStepM = 40,
  }) {
    if (coords.length < 2) return coords;
    final out = <NLatLng>[coords.first];
    for (int i = 1; i < coords.length; i++) {
      final a = coords[i - 1];
      final b = coords[i];
      final d = _haversineM(a.latitude, a.longitude, b.latitude, b.longitude);
      if (d > maxStepM) {
        final n = (d / maxStepM).ceil();
        for (int k = 1; k < n; k++) {
          final t = k / n;
          out.add(NLatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ));
        }
      }
      out.add(b);
    }
    return out;
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
  // ── 경로 방향 화살표 헬퍼 ──────────────────────────────────────────────────────

  /// 두 좌표 사이의 방위각 (0°=북, 시계방향)
  /// patternImage 생성 — NPathOverlay 가 경로 방향 자동 회전
  Future<NOverlayImage> _buildPatternImage() => NOverlayImage.fromWidget(
        widget: CustomPaint(
          painter: RouteArrowPainter(),
          size: const Size(10, 14),
        ),
        size: const Size(10, 14),
        context: context,
      );

  Future<void> _drawResultOnMap({
    bool fitCamera = true, // 후보 선택처럼 곧바로 자체 카메라 이동이 따라오면 false (이중 점프 방지)
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
    List<List<Map<String, dynamic>>>? greyRoutes, // 선택 안 된 대안 경로 (회색 선)
  }) async {
    if (_mapController == null) return;

    // 브랜드 로고 캐시 완료 대기 (최대 2초)
    if (!_brandImagesCached) {
      await GasStationMapBadge.precacheBrandImages(context);
      _brandImagesCached = true;
    }

    await _mapController!.clearOverlays(type: NOverlayType.pathOverlay);
    await _mapController!
        .clearOverlays(type: NOverlayType.multipartPathOverlay);
    await _mapController!.clearOverlays(type: NOverlayType.marker);

    // ── 경로 라인 ──
    final patternImg = await _buildPatternImage();

    // 선택 안 된 대안 경로를 회색으로 먼저 깔아 비교 표시 (선택 경로가 위에 그려짐)
    if (greyRoutes != null && greyRoutes.isNotEmpty) {
      for (int gi = 0; gi < greyRoutes.length; gi++) {
        final gpts = greyRoutes[gi];
        if (gpts.length < 2) continue;
        final gcoords = _densifyPath(_smoothPath(gpts
            .map((p) => NLatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList()));
        final greyOverlay = NPathOverlay(
          id: 'alt_route_grey_$gi',
          coords: gcoords,
          color: const Color(0xFFAEB6C2),
          width: 7,
          outlineColor: Colors.white,
          outlineWidth: 1,
        );
        greyOverlay.setGlobalZIndex(-250000); // 선택 경로(기본 -200000)보다 아래
        await _mapController!.addOverlay(greyOverlay);
      }
    }

    // path_segments 가 없으면(예: AI 결과 via 경로) 목적지 선택 때 받은 혼잡도 세그먼트
    // (_lastPathSegments)를 재사용 → 단색 대신 목적지 경로와 동일한 혼잡도 색으로 통일.
    final segs = (pathSegments != null && pathSegments.isNotEmpty)
        ? pathSegments
        : _lastPathSegments;
    if (segs != null && segs.isNotEmpty) {
      // ① NMultipartPathOverlay: 교통 정보 세그먼트별 색상
      final multiPaths = <NMultipartPath>[];

      for (int si = 0; si < segs.length; si++) {
        final seg = segs[si];
        final rawCoords = seg['coords'];
        if (rawCoords is! List || rawCoords.length < 2) continue;
        final coordsRaw = rawCoords
            .whereType<Map>()
            .map((c) => NLatLng(
                  (c['lat'] as num).toDouble(),
                  (c['lng'] as num).toDouble(),
                ))
            .toList();
        if (coordsRaw.length < 2) continue;
        final coords = _densifyPath(_smoothPath(coordsRaw));
        final congestion =
            seg['congestion'] is num ? (seg['congestion'] as num).toInt() : -1;
        final color = _congestionColor(congestion);
        multiPaths.add(NMultipartPath(
          coords: coords,
          color: color,
          outlineColor: Colors.transparent,
          passedColor: color.withValues(alpha: 0.28),
          passedOutlineColor: Colors.transparent,
        ));
      }

      if (multiPaths.isNotEmpty) {
        await _mapController!.addOverlay(NMultipartPathOverlay(
          id: 'result_route_traffic',
          paths: multiPaths,
          width: 8,
          outlineWidth: 0,
          patternImage: patternImg,
          patternInterval: 30,
        ));
      } else {
        debugPrint(
            '[AI_MAP_SEGMENTS] path_segments 존재하지만 유효 coords가 없어 multipart 렌더 실패');
      }
    } else if (pathPoints.length >= 2) {
      debugPrint('[AI_MAP_SEGMENTS] path_segments 없음/비어있음 -> 단색 경로로 폴백');
      final coordsRaw = pathPoints
          .map((p) => NLatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList();
      final coords = _densifyPath(_smoothPath(coordsRaw));
      await _mapController!.addOverlay(NPathOverlay(
        id: 'result_route',
        coords: coords,
        color: _congestionColor(-1),
        width: 8,
        outlineColor: Colors.transparent,
        outlineWidth: 0,
        patternImage: patternImg,
        patternInterval: 50,
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
      // 색으로 역할(주황=추천/파랑=비교/보라=선택) 구분하던 것 폐기(형 확정: 짜침) —
      // 후보는 전부 같은 톤, 1·2순위만 '추천 N위' 메달 배지 + 1순위 볼드 강조.
      final stIsTop = _lastRecIsDetour; // 추천이 우회면 st 가 1순위
      final c = stIsTop ? const Color(0xFF3B82F6) : const Color(0xFF64748B);
      // 사용자가 대안 선택 시 primary 강조는 짙은 파랑 (보라 폐기 — 파랑 단일 축)
      final isAltSelected =
          _selectedAltStationId != null && _selectedAltStationId!.isNotEmpty;
      final markerColor = isAltSelected ? const Color(0xFF2563EB) : c;
      final stMarker = NMarker(
        id: 'result_station',
        position: NLatLng(stLat, stLng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: stLabel,
          brand: stBrand,
          stationName: stName,
          borderColor: markerColor,
          textColor: markerColor,
          emphasizeBorder: stIsTop && !isAltSelected,
          recommendRank: isAltSelected ? null : (stIsTop ? 1 : 2),
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      await _mapController!.addOverlay(stMarker);
    }

    // st2=경로상. 추천이 경로상(우회 아님)이면 주황(추천색), 아니면 파랑(비교).
    if (st2Lat != null && st2Lng != null && st2Name.isNotEmpty) {
      final st2Label = st2Price != null && st2Price > 0
          ? '${_wonFmt.format(st2Price)}원'
          : st2Name;
      final st2IsTop = !_lastRecIsDetour; // 추천이 경로상이면 st2 가 1순위
      final c2 = st2IsTop ? const Color(0xFF3B82F6) : const Color(0xFF64748B);
      final st2Marker = NMarker(
        id: 'result_station2',
        position: NLatLng(st2Lat, st2Lng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: st2Label,
          brand: st2Brand,
          stationName: st2Name,
          borderColor: c2,
          textColor: c2,
          emphasizeBorder: st2IsTop,
          recommendRank: st2IsTop ? 1 : 2,
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

    // 대안 후보 마커 — 선택된 stationId 면 보라색 강조, 아니면 회색.
    // 마커 탭 시 미니 sheet 표시 (이름·가격·우회·"이걸로 선택" 버튼).
    const _kSelectedPurple = Color(0xFF2563EB); // 선택 강조 — 파랑 단일 축(보라 폐기)
    final altLats = <double>[];
    final altLngs = <double>[];
    if (alternatives != null) {
      int altIdx = 0;
      for (final alt in alternatives) {
        if (alt is! Map) {
          altIdx++;
          continue;
        }
        final altSt = alt['station'] is Map ? alt['station'] as Map : null;
        if (altSt == null) {
          altIdx++;
          continue;
        }
        final altLat =
            altSt['lat'] is num ? (altSt['lat'] as num).toDouble() : null;
        final altLng =
            altSt['lng'] is num ? (altSt['lng'] as num).toDouble() : null;
        if (altLat == null || altLng == null) {
          altIdx++;
          continue;
        }
        final altStationId = (altSt['id'] ?? '').toString();
        final isNearPrimary = stLat != null &&
            stLng != null &&
            (stLat - altLat).abs() < 0.0002 &&
            (stLng - altLng).abs() < 0.0002;
        final isNearSecondary = st2Lat != null &&
            st2Lng != null &&
            (st2Lat - altLat).abs() < 0.0002 &&
            (st2Lng - altLng).abs() < 0.0002;
        if (!isNearPrimary && !isNearSecondary) {
          final altPriceRaw = altSt['price_won_per_liter'];
          final altPriceVal = altPriceRaw is num ? altPriceRaw.round() : null;
          final altLabel = altPriceVal != null
              ? '${_wonFmt.format(altPriceVal)}원'
              : '후보${altIdx + 1}';
          final isSelected =
              altStationId.isNotEmpty && altStationId == _selectedAltStationId;
          // 서버가 잔량 부족 후보로 표시한 휴게소 — 마커도 빨강 톤 + ⚠ 로 명확히 구분.
          final isUnreachable = alt['unreachable'] == true;
          final altBorder =
              isSelected ? _kSelectedPurple : const Color(0xFFDDDDDD);
          final altText =
              isSelected ? _kSelectedPurple : const Color(0xFF1a1a1a);
          final altMarker = NMarker(
            id: 'result_alt_$altIdx',
            position: NLatLng(altLat, altLng),
            icon: await GasStationMapBadge.overlayImage(
              context,
              label: altLabel,
              brand: altSt['brand']?.toString(),
              stationName: altSt['name']?.toString(),
              borderColor: altBorder,
              textColor: altText,
              emphasizeBorder: isSelected,
              unreachable: isUnreachable,
            ),
            anchor: const NPoint(0.5, 1.0),
          );
          // 마커 탭 → 이 후보의 미니 카드 sheet
          final captured = Map<String, dynamic>.from(alt);
          altMarker.setOnTapListener((_) async {
            if (!await _tapGuard()) return; // 핀치 오탭 가드
            await _showStationMiniSheet(captured);
          });
          await _mapController!.addOverlay(altMarker);
          altLats.add(altLat);
          altLngs.add(altLng);
        }
        altIdx++;
      }
    }

    // 카메라: 전체 경로가 보이도록 fitBounds
    final allLats = [
      originLat,
      destLat,
      if (stLat != null) stLat,
      if (st2Lat != null) st2Lat,
      ...altLats,
    ];
    final allLngs = [
      originLng,
      destLng,
      if (stLng != null) stLng,
      if (st2Lng != null) st2Lng,
      ...altLngs,
    ];
    final minLat = allLats.reduce(min);
    final maxLat = allLats.reduce(max);
    final minLng = allLngs.reduce(min);
    final maxLng = allLngs.reduce(max);

    if (!fitCamera) {
      // fit 은 생략해도 경유지 배지 복원은 필요 (redraw 가 marker 를 지웠으므로)
      unawaited(_updateViaMarkers());
      return;
    }
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
    // 경로 redraw 가 marker 오버레이를 지우므로 경유지 배지 복원
    unawaited(_updateViaMarkers());
  }

  /// EV 직접선택 모드 — 후보 충전소 마커를 지도에 표시
  Future<void> _drawEvCandidateMarkers(
      List<Map<String, dynamic>> candidates) async {
    if (_mapController == null || candidates.isEmpty) return;
    // 아이콘(위젯 래스터) 병렬 생성 후 한 번에 addOverlayAll — 순차 await + 개별 add 제거.
    final futures = <Future<NMarker?>>[];
    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final lat = (c['lat'] as num?)?.toDouble();
      final lng = (c['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final avail = (c['available_count'] as num?)?.toInt() ?? 0;
      final total = (c['total_count'] as num?)?.toInt() ?? 0;
      final label = '$avail/$total';
      final color =
          avail > 0 ? const Color(0xFF1D9E75) : const Color(0xFFE8700A);
      futures.add(() async {
        final marker = NMarker(
          id: 'ev_candidate_$i',
          position: NLatLng(lat, lng),
          icon: await GasStationMapBadge.overlayImage(
            context,
            label: label,
            isEv: true,
            borderColor: color,
            textColor: color,
            emphasizeBorder: false,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        marker.setOnTapListener((_) async {
          if (!await _tapGuard()) return; // 핀치 오탭 가드
          _openEvStationDetail(c); // 상세 바텀시트
        });
        return marker;
      }());
    }
    final markers = (await Future.wait(futures)).whereType<NMarker>().toSet();
    if (_mapController == null || markers.isEmpty) return;
    await _mapController!.addOverlayAll(markers);
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
    bool fitCamera = true, // '지도에서 보기'는 false — 충전소로 이동한 카메라 유지
  }) async {
    if (_mapController == null) return;
    await _mapController!.clearOverlays();

    // 경로선 + 출발/도착 마커는 _drawResultOnMap 재사용 (stLat=null로 충전소 마커 생략)
    await _drawResultOnMap(
      fitCamera: fitCamera,
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
    // 추천 충전소 마커 (파랑 강조) — 탭하면 결과 시트의 해당 카드로 스크롤
    if (recommended != null) {
      final lat = (recommended['lat'] as num?)?.toDouble();
      final lng = (recommended['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final avail = (recommended['available_count'] as num?)?.toInt() ?? 0;
        final total = (recommended['total_count'] as num?)?.toInt() ?? 0;
        const color = Color(0xFF1D6FE0);
        final recStatId = recommended['statId']?.toString();
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
        if (recStatId != null && recStatId.isNotEmpty) {
          marker.setOnTapListener((_) async {
            if (!await _tapGuard()) return; // 핀치 오탭 가드
            await _focusResultStation(recStatId);
          });
        }
        await _mapController!.addOverlay(marker);
      }
    }

    // 대안 충전소 마커 (주황) — 탭하면 결과 시트의 해당 카드로 스크롤
    for (int i = 0; i < alternatives.length; i++) {
      final alt = alternatives[i];
      final lat = (alt['lat'] as num?)?.toDouble();
      final lng = (alt['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final avail = (alt['available_count'] as num?)?.toInt() ?? 0;
      final total = (alt['total_count'] as num?)?.toInt() ?? 0;
      const color = Color(0xFF64748B); // 대안 = 슬레이트 (주황 폐기 — 6a 마커 규칙)
      final altStatId = alt['statId']?.toString();
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
      if (altStatId != null && altStatId.isNotEmpty) {
        marker.setOnTapListener((_) async {
          if (!await _tapGuard()) return; // 핀치 오탭 가드
          await _focusResultStation(altStatId);
        });
      }
      await _mapController!.addOverlay(marker);
    }
    // 경로 redraw 가 marker 오버레이를 지우므로 경유지 배지 복원
    unawaited(_updateViaMarkers());
  }

  /// 결과 시트를 펼치고 해당 충전소 카드로 스크롤 (지도 마커 탭 핸들러)
  Future<void> _focusResultStation(String statId) async {
    // 시트가 작게 collapse 되어 있으면 먼저 펼침
    try {
      if (_sheetController.isAttached && _sheetController.size < 0.4) {
        await _sheetController.animateTo(
          0.55,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {}
    // EvResultBody 의 카드로 스크롤
    await _evResultBodyKey.currentState?.scrollToStation(statId);
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

  // ── TMAP path_features (passthrough) → 앱 segments 변환 ──
  // path_features: [{ coords:[{lat,lng}...], traffic: <원본> }, ...]
  // traffic 형식 둘 다 처리:
  //   1) 배열-of-배열  [[s,e,c,speed], ...]
  //   2) 스트링 단일/리스트 ["s,e,c,speed", ...] 또는 "s,e,c,speed"
  // TMAP congestion 스케일: 0=정보없음, 1=원활, 2=서행, 3=지체, 4=정체
  // → 앱 스케일(_congestionColor): 0=원활, 1=서행, 2=지체, 3=정체 (0/1=원활로 묶음)
  static int _tmapCongToApp(int tmapCong) {
    if (tmapCong <= 1) return 0;
    if (tmapCong >= 4) return 3;
    return tmapCong - 1; // 2→1, 3→2
  }

  static List<List<int>> _parseTmapTrafficEntries(dynamic raw) {
    if (raw == null) return const [];
    final out = <List<int>>[];
    final iterable = raw is List ? raw : [raw];
    for (final item in iterable) {
      if (item is List && item.length >= 3) {
        final s = (item[0] as num?)?.toInt();
        final e = (item[1] as num?)?.toInt();
        final c = (item[2] as num?)?.toInt();
        if (s != null && e != null && c != null) out.add([s, e, c]);
      } else if (item is String) {
        final parts =
            item.split(',').map((v) => int.tryParse(v.trim())).toList();
        if (parts.length >= 3 &&
            parts[0] != null &&
            parts[1] != null &&
            parts[2] != null) {
          out.add([parts[0]!, parts[1]!, parts[2]!]);
        }
      }
    }
    return out;
  }

  static List<Map<String, dynamic>>? _pathFeaturesToSegments(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final segments = <Map<String, dynamic>>[];
    for (final feat in raw) {
      if (feat is! Map) continue;
      final rawCoords = feat['coords'];
      if (rawCoords is! List || rawCoords.length < 2) continue;
      final coords = <Map<String, dynamic>>[];
      for (final p in rawCoords) {
        if (p is Map && p['lat'] is num && p['lng'] is num) {
          coords.add({
            'lat': (p['lat'] as num).toDouble(),
            'lng': (p['lng'] as num).toDouble(),
          });
        }
      }
      if (coords.length < 2) continue;

      final entries = _parseTmapTrafficEntries(feat['traffic']);
      if (entries.isEmpty) {
        // 교통정보 없는 LineString — 단일 세그먼트로 원활(0) 처리
        segments.add({'coords': coords, 'congestion': 0});
        continue;
      }

      entries.sort((a, b) => a[0].compareTo(b[0]));
      final lastIdx = coords.length - 1;
      var cursor = 0;
      for (final entry in entries) {
        final s = entry[0].clamp(0, lastIdx);
        final e = entry[1].clamp(s, lastIdx);
        final cong = _tmapCongToApp(entry[2]);
        if (s > cursor) {
          // 갭은 원활(0)로 채움
          final slice = coords.sublist(cursor, s + 1);
          if (slice.length >= 2)
            segments.add({'coords': slice, 'congestion': 0});
        }
        final segStart = s > cursor ? s : cursor;
        final slice = coords.sublist(segStart, e + 1);
        if (slice.length >= 2)
          segments.add({'coords': slice, 'congestion': cong});
        cursor = e;
      }
      if (cursor < lastIdx) {
        final slice = coords.sublist(cursor, lastIdx + 1);
        if (slice.length >= 2) segments.add({'coords': slice, 'congestion': 0});
      }
    }
    return segments.isEmpty ? null : segments;
  }

  // 응답 payload에서 segments를 추출 — TMAP path_features 우선, 없으면 Naver path_segments fallback.
  static List<Map<String, dynamic>>? _segmentsFromPayload(Map payload) {
    final fromFeatures = _pathFeaturesToSegments(payload['path_features']);
    if (fromFeatures != null && fromFeatures.isNotEmpty) return fromFeatures;
    return _parsePathSegments(payload['path_segments']);
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthM = 6371000.0;
    final r1 = lat1 * pi / 180, r2 = lat2 * pi / 180;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(r1) * cos(r2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * asin(min(1.0, sqrt(a)));
    return earthM * c;
  }

  static int _closestPathPointIndex(
      List<Map<String, dynamic>> pts, double lat, double lng) {
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
    required void Function(
            List<Map<String, dynamic>> pts, List<Map<String, dynamic>>? seg)
        apply,
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
    // 경유 좌표가 톨게이트/고속도로에 snap 되면 TMap/Naver 모두 진입→U턴 경로를 짠다
    // (목적지 먼저 갔다가 경유로 되돌아오는 폴리라인). 클라이언트 재길찾기도 같은 snap →
    // 억지로 U턴 경로를 그리지 않고 **직행 경로**를 그리고 주유소는 마커로만 노출한다.
    debugPrint(
        '[AI_MAP_ROUTE] 경유 경로 snap 의심(server=$serverSusp/client=$clientSusp) → 직행 경로로 표시(마커만)');
    apply(_lastPathPoints, null);
  }

  /// 지도 마커 탭 시 표시되는 미니 카드 sheet — 이름·주소·가격·우회 정보 +
  /// "이걸로 선택" 버튼 (선택 시 _showAltRouteOnMap 호출 → 보라색 강조 + 결과 카드 갱신).
  Future<void> _showStationMiniSheet(Map<String, dynamic> altItem) async {
    final st = altItem['station'] is Map
        ? Map<String, dynamic>.from(altItem['station'] as Map)
        : null;
    if (st == null) return;
    final id = (st['id'] ?? '').toString();
    final origName = (st['name'] ?? '').toString();
    final name =
        id.isEmpty ? origName : StationAliasService.resolveGas(id, origName);
    final addr = (st['address'] ?? '').toString();
    final priceRaw = st['price_won_per_liter'];
    final price = priceRaw is num ? priceRaw.round() : 0;
    final detourMin = altItem['detour_time_min'] is num
        ? (altItem['detour_time_min'] as num).round()
        : null;
    final detourIsNone = altItem['detour_is_none'] == true ||
        (detourMin != null && detourMin <= 0);
    // 유종 — 이 추천이 계산된 유종(선택 차량 or 글로벌 설정). 가격이 어느 유종 기준인지 표시.
    final box = Hive.box(AppConstants.settingsBox);
    final sv = _readSelectedVehicle(box);
    final fuelCode = sv?.fuelType ??
        (box.get(AppConstants.keyAiFuelType,
            defaultValue: FuelType.gasoline.code) as String);
    final fuel = FuelType.fromCode(fuelCode);
    final fuelColor = _fuelColor(fuel);
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 주유=파랑 단일 축 (형 확정 — 시트가 주황톤이라 지적). 유종 칩만 유종색 유지.
    final accentBlue =
        isDark ? AppColors.darkBlueBright : const Color(0xFF2563EB);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final metricBg =
            isDark ? const Color(0x14FFFFFF) : const Color(0xFFF6F8FA);
        final divider =
            isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE5E7EB);
        return Container(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, MediaQuery.of(ctx).padding.bottom + 20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              // 이름 + 유종 칩
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 16.5,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF1A1A2E))),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color:
                            fuelColor.withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(fuel.label,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: fuelColor)),
                  ),
                ],
              ),
              if (addr.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(addr,
                    style: const TextStyle(
                        fontSize: 12, height: 1.35, color: Color(0xFF6B7280))),
              ],
              const SizedBox(height: 16),
              // 리터당 · 우회 메트릭 (소프트 카드 + 구분선)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                    color: metricBg, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(
                      child: _miniSheetMetric(
                          '리터당', '${_wonFmt.format(price)}원',
                          valueColor: accentBlue, big: true)),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 30, color: divider),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _miniSheetMetric(
                    '우회',
                    detourIsNone
                        ? '우회 없음'
                        : (detourMin != null ? '+$detourMin분' : '—'),
                  )),
                ]),
              ),
              // "이걸로 선택" 버튼 제거 — 마커 탭은 정보 확인 용도. 후보 변경은 결과 화면의
              // '다른 후보 → 확인' 버튼에서.
              if (id.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                            builder: (_) => GasDetailScreen(stationId: id)),
                      );
                    },
                    icon: Icon(Icons.storefront_outlined,
                        size: 17, color: accentBlue),
                    label: Text('주유소 상세보기',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: accentBlue)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side:
                          BorderSide(color: accentBlue.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // 유종별 강조색.
  Color _fuelColor(FuelType f) {
    switch (f) {
      case FuelType.premium:
        return const Color(0xFFDC2626); // 고급휘발유 — 레드
      case FuelType.diesel:
        return const Color(0xFF16A34A); // 경유 — 그린
      case FuelType.lpg:
        return const Color(0xFF2563EB); // LPG — 블루
      case FuelType.gasoline:
        return const Color(0xFFE8700A); // 휘발유 — 오렌지
    }
  }

  Widget _miniSheetMetric(String label, String value,
          {Color? valueColor, bool big = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: big ? 17 : 14,
                  fontWeight: FontWeight.w800,
                  color: valueColor)),
        ],
      );

  // ── 다른 후보 경로보기 ──
  // 지도 그리기 세대 — 후보를 연달아 누르면 앞선 draw 의 남은 await 가 뒤에 끼어들어
  // 경로선/마커가 섞였다(형 제보 '경로 표시가 다 꼬여버림'). 최신 요청만 반영한다.
  int _mapDrawGen = 0;

  Future<void> _showAltRouteOnMap(Map<String, dynamic> altItem) async {
    if (_destLat == null || _destLng == null) return;
    final gen = ++_mapDrawGen;
    await _collapseResultSheetForMapFocus();
    if (gen != _mapDrawGen) return;
    final st = altItem['station'] is Map ? altItem['station'] as Map : null;
    if (st == null) return;
    final stLat = _asDouble(st['lat']);
    final stLng = _asDouble(st['lng']);
    if (stLat == null || stLng == null) return;
    final stName = st['name']?.toString() ?? '';
    final priceL = st['price_won_per_liter'] is num
        ? (st['price_won_per_liter'] as num).round()
        : 0;
    // 보라색 강조용 stationId — _drawResultOnMap 안 (await chain) 내부에서 사용되므로
    // 가장 빨리 설정. await 후 set 하면 그 사이 다른 redraw 가 끼어들면 blue 로 그려진다.
    _selectedAltStationId = (st['id'] ?? '').toString();

    // 형 확정 v2: 탭 즉시 카메라부터 — 경로 확정(OSRM 교차검증/폴백 조회)을 기다렸다
    // 그리고 나서 이동하면 "한참 있다 한 번 더 그리고 이동"이 된다. 카메라 완료 후
    // 경로를 확정해 오버레이만 갱신 (draw·카메라 동시 실행은 네이티브 팅김 이력).
    if (!mounted || _mapController == null) return;
    try {
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(stLat, stLng),
          zoom: 14,
        )..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 500)),
      );
    } catch (_) {}
    if (gen != _mapDrawGen) return;

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    final vrMap = altItem['via_route'] is Map
        ? altItem['via_route'] as Map<String, dynamic>
        : null;
    var usedServerAlt = false;
    if (vrMap != null) {
      final parsed = _pathPointsFromServerJson(vrMap['path_points']);
      if (parsed != null) {
        await _maybeReplaceViaRouteFromClient(
          serverPts: parsed,
          serverSeg: _segmentsFromPayload(vrMap),
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
          startLat: _lastStartLat,
          startLng: _lastStartLng,
          goalLat: _destLat!,
          goalLng: _destLng!,
          waypointLat: stLat,
          waypointLng: stLng,
          vias: _viaCoords,
          engine: RouteEnginePref.get(),
        );
        if (vr['success'] == true) {
          final parsed = _pathPointsFromServerJson(vr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _segmentsFromPayload(vr);
          _debugSegmentStats(
            label: 'alternative.client.getDrivingRoute(fallback)',
            pathSegments: pathSegments,
            pathPoints: pathPoints,
          );
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint('[ai-alt] alternative getDrivingRoute 실패: $e');
      }
    }

    // 다른 후보로 선택 → 해당 station id 보라색 강조 (이미 함수 시작 시 설정함)
    // ★ await 로 순차화 — draw(오버레이 clear/add)와 카메라 애니메이션이 동시에 돌면
    //   NaverMap 네이티브에서 충돌해 '지도 가다가 팅김'(크래시) 발생. 그려진 뒤 카메라 이동.
    if (gen != _mapDrawGen) return; // 더 최근 탭이 들어옴 → 이 draw 는 버린다
    try {
      await _drawResultOnMap(
        fitCamera: false, // 아래 scrollAndZoomTo 가 카메라 담당 — fit→이동 이중 점프 방지
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
    } catch (e) {
      if (kDebugMode) debugPrint('[alt] _drawResultOnMap 실패: $e');
    }

    // 카메라는 함수 초입에서 이미 이동 — 여기서 또 움직이면 이중 점프.
  }

  // ── 비교 카드 탭 시 해당 경유 경로 지도에 그리기 ──
  Future<void> _showCompareCardRouteOnMap(
      Map<String, dynamic> stationData) async {
    if (_destLat == null || _destLng == null) return;
    final gen = ++_mapDrawGen;
    await _collapseResultSheetForMapFocus();
    if (gen != _mapDrawGen) return;
    final st =
        stationData['station'] is Map ? stationData['station'] as Map : null;
    if (st == null) return;
    final stLat = _asDouble(st['lat']);
    final stLng = _asDouble(st['lng']);
    if (stLat == null || stLng == null) return;
    final stName = st['name']?.toString() ?? '';
    final priceL = st['price_won_per_liter'] is num
        ? (st['price_won_per_liter'] as num).round()
        : 0;

    // 탭 즉시 카메라부터 (주유·충전 공통 규칙 — 형 확정 v2)
    if (!mounted || _mapController == null) return;
    try {
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(stLat, stLng),
          zoom: 14,
        )..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 500)),
      );
    } catch (_) {}
    if (gen != _mapDrawGen) return;

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    final vrMap = stationData['via_route'] is Map
        ? stationData['via_route'] as Map<String, dynamic>
        : null;
    if (vrMap != null) {
      final parsed = _pathPointsFromServerJson(vrMap['path_points']);
      if (parsed != null) {
        await _maybeReplaceViaRouteFromClient(
          serverPts: parsed,
          serverSeg: _segmentsFromPayload(vrMap),
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
          startLat: _lastStartLat,
          startLng: _lastStartLng,
          goalLat: _destLat!,
          goalLng: _destLng!,
          waypointLat: stLat,
          waypointLng: stLng,
          vias: _viaCoords,
          engine: RouteEnginePref.get(),
        );
        if (vr['success'] == true) {
          final parsed = _pathPointsFromServerJson(vr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _segmentsFromPayload(vr);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ai-compare] getDrivingRoute 실패: $e');
      }
    }

    if (!mounted || gen != _mapDrawGen) return;
    _drawResultOnMap(
      fitCamera: false, // 카메라는 이미 해당 주유소에 — 경로 fit 으로 뺏지 말 것
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
      showAppToast(context, '목적지를 선택해 주세요.');
      return;
    }
    // 서드파티 AI 문구 동의 (첫 사용 1회 고지)
    final aiOk = await AiConsent.ensure(context);
    if (!mounted) return;

    final box = Hive.box(AppConstants.settingsBox);
    VehicleProfile? selectedVehicle;
    {
      final selectedId =
          box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded
              .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
              .toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
              (v) => v?.id == selectedId,
              orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    if (selectedVehicle == null || !selectedVehicle.isEV) {
      showAppToast(context, '전기차 프로필을 선택해 주세요.');
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
        showAppToast(context, '현재 위치를 가져올 수 없습니다.', isError: true);
        return;
      }
      startLat = loc.lat;
      startLng = loc.lng;
    }

    setState(() {
      _aiAnalyzing = true;
      _errorMessage = null;
    });

    // 미리보기에서 이미 경로를 받아놨으면 재사용, 아니면 새로 fetch
    // (2점 = origin/dest만 있는 직선 폴백 → 추천 정확도 박살나므로 재fetch 강제)
    // 사용자가 고른 경로(추천/고속도로우선)가 있으면 그 폴리라인을 우선 사용.
    final selPts = _selectedRoutePoints();
    var pathPoints = selPts != null && selPts.length >= 2
        ? selPts
        : (_lastPathPoints.length >= 3
            ? _lastPathPoints
            : <Map<String, dynamic>>[
                {'lat': startLat, 'lng': startLng},
                {'lat': _destLat!, 'lng': _destLng!},
              ]);
    List<Map<String, dynamic>>? pathSegments =
        selPts != null ? _selectedRouteSegments() : _lastPathSegments;
    int? directDurationMs = _selectedRouteDurationMs();

    if (selPts == null &&
        (pathPoints.length < 3 ||
            _lastStartLat != startLat ||
            _lastStartLng != startLng)) {
      try {
        final dr = await ApiService().getDrivingRoute(
          startLat: startLat,
          startLng: startLng,
          goalLat: _destLat!,
          goalLng: _destLng!,
        );
        if (dr['success'] == true) {
          if (dr['duration_ms'] is num)
            directDurationMs = (dr['duration_ms'] as num).round();
          final parsed = _pathPointsFromServerJson(dr['path_points']);
          if (parsed != null) pathPoints = parsed;
          pathSegments = _segmentsFromPayload(dr);
          _lastStartLat = startLat;
          _lastStartLng = startLng;
          _lastPathPoints = pathPoints;
          _lastPathSegments = pathSegments;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ev-analyze] getDrivingRoute 실패: $e');
      }
    }

    try {
      final data = await ApiService().postEvAiRecommend({
        'batteryPercent': selectedVehicle.currentLevelPercent,
        'batteryCapacityKwh': selectedVehicle.batteryCapacity,
        'efficiencyKmPerKwh': selectedVehicle.evEfficiency,
        'targetSocPercent': selectedVehicle.targetChargePercent, // 목표 충전 %
        // 잔량 조건 — 사용자가 직접 정했을 때만. 안 보내면 서버 원격설정 기본값이 쓰인다.
        if (_socConditionUserSet) ...{
          'minArrivalSocPercent': _evMinArrivalSoc,
          'destMinSocPercent': _evDestMinSoc,
        },
        'chargerType': _evChargerType,
        'originLat': startLat,
        'originLng': startLng,
        'destLat': _destLat,
        'destLng': _destLng,
        'pathPoints': pathPoints,
        if (directDurationMs != null) 'directDurationMs': directDurationMs,
        // 우회시간 기준 경로에 포함 — 안 보내면 경유지 없는 길과 비교하게 된다.
        if (_viaCoords.isNotEmpty) 'vias': _viaCoords,
        // 서버가 우회시간을 '내가 화면에서 본 경로'와 같은 엔진·같은 옵션으로 재게 한다.
        'engine': RouteEnginePref.get(),
        'route_key': _selectedRouteKey,
        'highwayOnly': _evHighwayOnly,
        if (_preferredEvOperators.isNotEmpty)
          'operators': _preferredEvOperators.toList(),
        // 브랜드 충전소 — AI 탭 사업자·브랜드 시트의 '자체 선택'만 전달
        // (지도·홈 필터의 brands 와 독립 — 몰래 좁혀지는 함정 방지, 형 확정)
        if (_preferredEvBrands.isNotEmpty)
          'brands': _preferredEvBrands.toList(),
        if (_evChargerType == 'FAST' && _evFastOutputs.isNotEmpty)
          'fastOutputs': _evFastOutputs.toList(),
        'ai_text': AiConsent.value == true, // 서드파티 AI 문구 동의
      });

      if (!mounted) return;

      final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';

      // 사용자가 조건을 직접 안 정했으면 서버가 실제로 쓴 값으로 칩 표시를 맞춘다.
      // (원격설정으로 기본값을 튜닝했을 때 앱 하드코딩 값이 그대로 보이면 칩이 거짓말한다)
      final srvCond = data['soc_conditions'];
      if (!_socConditionUserSet && srvCond is Map) {
        // 표시값은 클램프하지 않는다 — 슬라이더 범위(0~50)와 별개다.
        // 원격설정이 50 을 넘으면 칩이 깎인 값을 보여줘 거짓말이 된다.
        final mn = (srvCond['min_arrival_soc'] as num?)?.round();
        final dm = (srvCond['dest_min_soc'] as num?)?.round();
        if (mn != null) _evMinArrivalSoc = mn;
        if (dm != null) _evDestMinSoc = dm;
      }

      setState(() {
        _isEvResultMode = true;
        _lastResultData = data;
        _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
      });
      _triggerEvSavingsReveal(data);

      // 지도에 경로 + 마커 그리기
      final recommended = data['recommended'] is Map
          ? data['recommended'] as Map<String, dynamic>
          : null;
      final alternatives = data['alternatives'] is List
          ? (data['alternatives'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
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
      final rl = rateLimitMessage(e, feature: 'AI 충전소 추천');
      if (rl != null) {
        showAppDialog<void>(context,
            icon: Icons.schedule_rounded,
            title: '오늘은 여기까지!',
            message: rl,
            primaryLabel: '확인');
      } else {
        setState(() => _errorMessage = '충전소 추천에 실패했습니다. 다시 시도해 주세요.');
        unawaited(RatingPromptService.markNegativeSignal()); // 짜증 직후 평점 안내 스킵
      }
    } finally {
      if (mounted) setState(() => _aiAnalyzing = false);
    }
  }

  // EV 카드 "지도에서 경로 보기" 탭
  Future<void> _showEvStationRouteOnMap(Map<String, dynamic> station) async {
    if (_destLat == null || _destLng == null) return;
    final gen = ++_mapDrawGen;
    await _collapseResultSheetForMapFocus();
    if (gen != _mapDrawGen) return;

    final stLat = (station['lat'] as num?)?.toDouble();
    final stLng = (station['lng'] as num?)?.toDouble();
    if (stLat == null || stLng == null) return;

    // 형 확정: 다른 마커를 다 지우지 말 것 — 탭한 곳만 강조(recommended 슬롯)하고
    // 나머지는 전부 대안 마커로 유지한다. 주유소처럼 "사라지지 않고 확대만".
    // 직접선택 모드도 동일 — 후보 리스트 전체를 유지해야 한다(형 제보: 다 사라짐).
    final tappedId = station['statId']?.toString();
    final others = <Map<String, dynamic>>[];
    void addOther(dynamic m) {
      if (m is! Map) return;
      final mm = Map<String, dynamic>.from(m);
      if (tappedId != null && mm['statId']?.toString() == tappedId) return;
      others.add(mm);
    }

    if (_isEvSelectMode) {
      for (final c in _evSelectCandidates) {
        addOther(c);
      }
    } else if (_lastResultData != null) {
      addOther(_lastResultData!['recommended']);
      final alts = _lastResultData!['alternatives'];
      if (alts is List) alts.forEach(addOther);
    }

    // 형 확정 v2: 탭 즉시 카메라부터 — 경로 조회를 기다렸다 "한참 있다 지도 한 번 더
    // 그리고 이동"하는 건 없으니만 못하다. 조회는 백그라운드로 먼저 던져두고,
    // 카메라 애니메이션이 끝난 뒤 도착한 경로로 오버레이만 갱신한다
    // (draw 와 카메라 동시 실행은 네이티브 팅김 이력 — 순차 유지).
    final routeFuture = ApiService().getDrivingRoute(
      startLat: _lastStartLat,
      startLng: _lastStartLng,
      goalLat: _destLat!,
      goalLng: _destLng!,
      waypointLat: stLat,
      waypointLng: stLng,
      vias: _viaCoords,
      engine: RouteEnginePref.get(),
    );
    try {
      await _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(stLat, stLng),
          zoom: 14,
        )..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 500)),
      );
    } catch (_) {}

    var pathPoints = _lastPathPoints;
    List<Map<String, dynamic>>? pathSegments;
    try {
      final vr = await routeFuture;
      if (vr['success'] == true) {
        final parsed = _pathPointsFromServerJson(vr['path_points']);
        if (parsed != null) pathPoints = parsed;
        pathSegments = _segmentsFromPayload(vr);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ev-route] getDrivingRoute 실패: $e');
    }

    if (!mounted || gen != _mapDrawGen) return; // 더 최근 탭이 들어옴
    await _drawEvResultOnMap(
      fitCamera: false, // 카메라는 이미 충전소에 가 있다 — 경로 fit 으로 뺏지 말 것
      pathPoints: pathPoints,
      pathSegments: pathSegments,
      originLat: _lastStartLat,
      originLng: _lastStartLng,
      destLat: _destLat!,
      destLng: _destLng!,
      recommended: station,
      alternatives: others,
    );
    if (!mounted || gen != _mapDrawGen) return;

    if (_isEvSelectMode) {
      // 직접선택 리스트에서 호출 → 결과 모드의 단일 카드로 전환.
      // 사용자가 시트 collapse → 다시 펼치면 그 station 상세 카드 그대로 보이게.
      // 50개 리스트는 _prevEvSelectCandidates 에 백업 → 뒤로가기로 복원 가능.
      setState(() {
        _prevEvSelectCandidates = List.of(_evSelectCandidates);
        _isEvSelectMode = false;
        _evSelectCandidates = [];
        _isEvResultMode = true;
        _lastResultData = {
          'charger_type': _evChargerType,
          'reachable_distance_km': 0.0,
          'recommended': station,
          // 나머지 후보 유지 — 비우면 다음 redraw 에서 마커가 통째로 사라진다(형 제보).
          'alternatives': others,
          'total_candidates': null,
          'filtered_out_count': 0,
        };
      });
      // 시트는 작게 collapse → 사용자가 지도 path 먼저 확인 → 펼치면 상세 카드 보임
      try {
        if (_sheetController.isAttached) {
          await _sheetController.animateTo(
            0.18,
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
      showAppToast(context, '목적지를 선택해 주세요.');
      return;
    }

    final box = Hive.box(AppConstants.settingsBox);
    VehicleProfile? selectedVehicle;
    {
      final selectedId =
          box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded
              .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
              .toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
              (v) => v?.id == selectedId,
              orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    if (selectedVehicle == null || !selectedVehicle.isEV) return;

    double startLat, startLng;
    if (_originLat != null && _originLng != null) {
      startLat = _originLat!;
      startLng = _originLng!;
    } else {
      final loc = await _resolveCurrentLocationForStart();
      if (loc == null) return;
      startLat = loc.lat;
      startLng = loc.lng;
    }

    setState(() {
      _userSelecting = true;
      _userSelectingMessage = '경로상 충전소 목록 불러오는 중...';
      _errorMessage = null;
    });

    // 미리보기에서 이미 경로를 받아놨으면 재사용
    // (2점 = origin/dest만 있는 직선 폴백 → 추천 정확도 박살나므로 재fetch 강제)
    var pathPoints = _lastPathPoints.length >= 3
        ? _lastPathPoints
        : <Map<String, dynamic>>[
            {'lat': startLat, 'lng': startLng},
            {'lat': _destLat!, 'lng': _destLng!},
          ];

    if (pathPoints.length < 3 ||
        _lastStartLat != startLat ||
        _lastStartLng != startLng) {
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
          _lastPathSegments = _segmentsFromPayload(dr);
          _lastStartLat = startLat;
          _lastStartLng = startLng;
          _lastPathPoints = pathPoints;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ev-userselect] getDrivingRoute 실패: $e');
      }
    }

    try {
      final data = await ApiService().postEvAiRecommend({
        'batteryPercent': selectedVehicle.currentLevelPercent,
        'batteryCapacityKwh': selectedVehicle.batteryCapacity,
        'efficiencyKmPerKwh': selectedVehicle.evEfficiency,
        'targetSocPercent': selectedVehicle.targetChargePercent, // 목표 충전 %
        'chargerType': _evChargerType,
        'originLat': startLat,
        'originLng': startLng,
        'destLat': _destLat,
        'destLng': _destLng,
        'pathPoints': pathPoints,
        'userSelect': true,
        if (_viaCoords.isNotEmpty) 'vias': _viaCoords,
        // 서버가 우회시간을 '내가 화면에서 본 경로'와 같은 엔진·같은 옵션으로 재게 한다.
        'engine': RouteEnginePref.get(),
        'route_key': _selectedRouteKey,
        'highwayOnly': _evHighwayOnly,
        if (_preferredEvOperators.isNotEmpty)
          'operators': _preferredEvOperators.toList(),
        // 브랜드 충전소 — AI 탭 사업자·브랜드 시트의 '자체 선택'만 전달
        // (지도·홈 필터의 brands 와 독립 — 몰래 좁혀지는 함정 방지, 형 확정)
        if (_preferredEvBrands.isNotEmpty)
          'brands': _preferredEvBrands.toList(),
        if (_evChargerType == 'FAST' && _evFastOutputs.isNotEmpty)
          'fastOutputs': _evFastOutputs.toList(),
        'ai_text': AiConsent.value == true, // 서드파티 AI 문구 동의
      });
      if (!mounted) return;

      final candidates = data['candidates'] is List
          ? (data['candidates'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
          : <Map<String, dynamic>>[];

      if (candidates.isEmpty) {
        setState(() => _errorMessage = '경로 내 이용 가능한 충전소가 없어요.');
        unawaited(RatingPromptService.markNegativeSignal());
        return;
      }

      // 지도에 전체 후보 마커 표시
      final originLabel = _originName ?? _currentLocationAddress ?? '현재 위치';
      setState(() {
        _isEvSelectMode = true;
        _evSelectCandidates = candidates;
        _evSelectSpeedRelaxed = data['speed_relaxed'] == true;
        _lastRouteSummary = '$originLabel → ${_destName ?? '목적지'}';
      });

      // 경로 + 출발/도착 마커 그리기 (후보 마커는 _drawEvCandidateMarkers에서 별도 처리)
      _drawResultOnMap(
        pathPoints: pathPoints,
        pathSegments: _lastPathSegments,
        originLat: startLat,
        originLng: startLng,
        stLat: null,
        stLng: null,
        stName: '',
        destLat: _destLat!,
        destLng: _destLng!,
        alternatives: null,
      );
      // EV 후보 마커 표시
      await _drawEvCandidateMarkers(candidates);
    } catch (e) {
      if (kDebugMode) debugPrint('[ev-userselect] postEvAiRecommend 실패: $e');
      if (!mounted) return;
      // 한도 초과(429)면 "오늘은 여기까지" 팝업 — 직접선택도 AI 분석과 합산 한도라서.
      final rl = rateLimitMessage(e, feature: 'AI 충전소 추천');
      if (rl != null) {
        showAppDialog<void>(context,
            icon: Icons.schedule_rounded,
            title: '오늘은 여기까지!',
            message: rl,
            primaryLabel: '확인');
      } else {
        setState(() => _errorMessage = '충전소 목록을 불러오는데 실패했습니다.');
      }
    } finally {
      if (mounted) setState(() => _userSelecting = false);
    }
  }

  // EV 사용자 선택 모드 — 리스트에서 충전소 탭 → 인라인 상세 바텀시트 (리스트 유지)
  Future<void> _openEvStationDetail(Map<String, dynamic> station) async {
    final statId = station['statId']?.toString();
    if (statId == null || !mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => EvStationDetailSheet(
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

  // ── 현재위치 FAB (하단 패널 Column 내부에서 사용) ───────────────────────
  Widget _buildMyLocationFab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _moveToMyLocation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (_isLocating || _isAtMyLocation)
              ? kPrimary
              : (isDark ? AppColors.darkMapOverlay : Colors.white),
          shape: BoxShape.circle,
          border: isDark && !(_isLocating || _isAtMyLocation)
              ? Border.all(color: AppColors.darkCardBorder, width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
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
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : const Color(0xFF666666))),
      ),
    );
  }

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
    await _mapController?.clearOverlays(
        type: NOverlayType.multipartPathOverlay);
    await _mapController?.clearOverlays(
        type: NOverlayType.arrowheadPathOverlay);
    await _mapController?.clearOverlays(type: NOverlayType.marker);
    _moveToMyLocation();
  }

  // ── AI 추천 경로로 복원 ──
  void _resetToAiRec() {
    if (_destLat == null || _destLng == null) return;
    _selectedAltStationId = null; // 선택 초기화 → 모든 alt 마커 회색 복귀
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
      showAppToast(context, '목적지를 선택해 주세요.');
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
        showAppToast(context, '현재 위치를 가져올 수 없습니다.', isError: true);
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
        startLat: startLat,
        startLng: startLng,
        goalLat: _destLat!,
        goalLng: _destLng!,
        vias: _viaCoords,
        engine: RouteEnginePref.get(),
      );
      if (dr['success'] == true) {
        final raw = dr['path_points'];
        if (raw is List && raw.length >= 2) {
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
          if (parsed.length >= 2) pathPoints = parsed;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[user-select] getDrivingRoute 실패: $e');
    }

    _lastStartLat = startLat;
    _lastStartLng = startLng;
    _lastPathPoints = pathPoints;

    // 경로상 주유소 목록 불러오기
    final box = Hive.box(AppConstants.settingsBox);
    // 선택 차량 프로필 = 단일 소스. 글로벌 키(keyAiTankCapacity 등)는 '차량 없을 때만' fallback.
    // (글로벌 키는 가스/EV·다차량이 공유하는 단일 슬롯이라 프로필과 어긋났음 → 카드·계산 불일치 버그)
    final sv = _readSelectedVehicle(box);
    final fuelCode = sv?.fuelType ??
        (box.get(AppConstants.keyAiFuelType,
            defaultValue: FuelType.gasoline.code) as String);
    final tankCapacity = sv == null
        ? (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
            .toDouble()
        : (sv.isEV ? sv.batteryCapacity : sv.tankCapacity);
    final efficiency = sv == null
        ? (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
            .toDouble()
        : (sv.isEV ? sv.evEfficiency : sv.efficiency);

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
        'engine': RouteEnginePref.get(), // 결과 지도 경유 경로를 같은 엔진으로
        'path_points': pathPoints,
        if (_viaCoords.isNotEmpty) 'vias': _viaCoords,
        // 서버가 우회시간을 '내가 화면에서 본 경로'와 같은 엔진·같은 옵션으로 재게 한다.
        'route_key': _selectedRouteKey,
        'highway_only': _gasHighwayOnly,
        if (_preferredGasBrands.isNotEmpty)
          'preferred_brands': _preferredGasBrands
              .expand((k) => k == 'RTO' ? const ['RTO', 'RTX'] : [k])
              .toList(),
      },
    };

    try {
      final data = await ApiService().postRefuelRouteStations(body);
      if (!mounted) return;

      final stations = data['stations'] is List ? data['stations'] as List : [];
      if (stations.isEmpty) {
        setState(() => _userSelecting = false);
        unawaited(RatingPromptService.markNegativeSignal());
        if (!mounted) return;
        showAppToast(context, '경로상 주유소를 찾을 수 없습니다.', isError: true);
        return;
      }

      final stationList = stations
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

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
      setState(() => _userSelecting = false);
      // 한도 초과(429)면 직접선택 버튼 단계에서 "오늘은 여기까지" 팝업 (fail-fast).
      final rl = rateLimitMessage(e, feature: 'AI 주유소 추천');
      if (rl != null) {
        showAppDialog<void>(context,
            icon: Icons.schedule_rounded,
            title: '오늘은 여기까지!',
            message: rl,
            primaryLabel: '확인');
      } else {
        setState(() => _errorMessage = '주유소 목록을 불러오는데 실패했습니다.');
        showAppToast(context, '오류: $e', isError: true);
      }
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

  /// 메인 경로 폴리라인을 _drawResultOnMap 과 동일하게 그린다.
  /// 혼잡도 세그먼트(pathSegments)가 있으면 구간별 색(NMultipartPathOverlay),
  /// 없으면 단색 폴백. 직접선택/비교 등 다른 화면도 이걸 써서 스타일을 통일.
  Future<void> _drawMainRoute(
    String id,
    List<Map<String, dynamic>> pathPoints,
    List<Map<String, dynamic>>? pathSegments,
  ) async {
    if (_mapController == null) return;
    final patternImg = await _buildPatternImage();

    if (pathSegments != null && pathSegments.isNotEmpty) {
      final multiPaths = <NMultipartPath>[];
      for (final seg in pathSegments) {
        final rawCoords = seg['coords'];
        if (rawCoords is! List || rawCoords.length < 2) continue;
        final coordsRaw = rawCoords
            .whereType<Map>()
            .map((c) => NLatLng(
                (c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()))
            .toList();
        if (coordsRaw.length < 2) continue;
        final coords = _densifyPath(_smoothPath(coordsRaw));
        final congestion =
            seg['congestion'] is num ? (seg['congestion'] as num).toInt() : -1;
        final color = _congestionColor(congestion);
        multiPaths.add(NMultipartPath(
          coords: coords,
          color: color,
          outlineColor: Colors.transparent,
          passedColor: color.withValues(alpha: 0.28),
          passedOutlineColor: Colors.transparent,
        ));
      }
      if (multiPaths.isNotEmpty) {
        await _mapController!.addOverlay(NMultipartPathOverlay(
          id: id,
          paths: multiPaths,
          width: 8,
          outlineWidth: 0,
          patternImage: patternImg,
          patternInterval: 30,
        ));
        return;
      }
    }

    if (pathPoints.length >= 2) {
      final coordsRaw = pathPoints
          .map((p) => NLatLng(
              (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
          .toList();
      final coords = _densifyPath(_smoothPath(coordsRaw));
      await _mapController!.addOverlay(NPathOverlay(
        id: id,
        coords: coords,
        color: _congestionColor(-1),
        width: 8,
        outlineColor: Colors.transparent,
        outlineWidth: 0,
        patternImage: patternImg,
        patternInterval: 50,
      ));
    }
  }

  Future<void> _drawSelectModeMap() async {
    if (_mapController == null || _selectableStations == null) return;

    // 브랜드 로고 캐시 완료 대기 — 첫 렌더에서 로고 없는 배지 방지 (_drawResultOnMap 과 동일)
    if (!_brandImagesCached) {
      await GasStationMapBadge.precacheBrandImages(context);
      _brandImagesCached = true;
    }

    await _mapController!.clearOverlays();

    // 경로 그리기 — 목적지 입력 경로(_drawResultOnMap)와 동일 렌더(혼잡도 구간색).
    await _drawMainRoute('select_route', _lastPathPoints, _lastPathSegments);

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
        ? _selectableStations!
            .where((s) => s['is_highway_rest_area'] == true)
            .toList()
        : _selectableStations!;

    // 최저가 ID 찾기
    String? cheapestId;
    int? cheapestPrice;
    for (final st in visibleStations) {
      final p = st['price_won_per_liter'] is num
          ? (st['price_won_per_liter'] as num).round()
          : null;
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
      final price = st['price_won_per_liter'] is num
          ? (st['price_won_per_liter'] as num).round()
          : null;

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
          borderColor = const Color(0xFF7B5EA7); // 선택 시트와 동일 (A=보라)
          textColor = const Color(0xFF7B5EA7);
          emphasize = true;
        } else if (isB) {
          label = price != null ? 'B ${_wonFmt.format(price)}원' : 'B';
          borderColor = kCompareBlue;
          textColor = kCompareBlue;
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
            stationName: st['name']?.toString(),
            borderColor: borderColor,
            textColor: textColor,
            emphasizeBorder: emphasize,
          ),
          anchor: const NPoint(0.5, 1.0),
        );
        marker.setOnTapListener((_) async {
          if (!_isSelectMode || _selectableStations == null) return;
          if (!await _tapGuard()) return; // 핀치 오탭 가드
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
    final allLats = [
      _lastStartLat,
      _destLat!,
      ...visibleStations.map((s) {
        final lat = s['lat'];
        return lat is num ? lat.toDouble() : _lastStartLat;
      })
    ];
    final allLngs = [
      _lastStartLng,
      _destLng!,
      ...visibleStations.map((s) {
        final lng = s['lng'];
        return lng is num ? lng.toDouble() : _lastStartLng;
      })
    ];

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

    final stA = _selectableStations!
        .firstWhere((s) => s['id']?.toString() == _selectedStationAId);
    final stB = _selectableStations!
        .firstWhere((s) => s['id']?.toString() == _selectedStationBId);

    setState(() {
      _userSelecting = true;
      _userSelectingMessage = '선택한 2곳 비교 분석 중...';
      _isSelectSheetVisible = false; // 시트 닫기 (인라인)
    });

    final box = Hive.box(AppConstants.settingsBox);
    // 선택 차량 프로필 = 단일 소스. 글로벌 키(keyAiTankCapacity 등)는 '차량 없을 때만' fallback.
    // (글로벌 키는 가스/EV·다차량이 공유하는 단일 슬롯이라 프로필과 어긋났음 → 카드·계산 불일치 버그)
    final sv = _readSelectedVehicle(box);
    final fuelCode = sv?.fuelType ??
        (box.get(AppConstants.keyAiFuelType,
            defaultValue: FuelType.gasoline.code) as String);
    final tankCapacity = sv == null
        ? (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
            .toDouble()
        : (sv.isEV ? sv.batteryCapacity : sv.tankCapacity);
    final efficiency = sv == null
        ? (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
            .toDouble()
        : (sv.isEV ? sv.evEfficiency : sv.efficiency);

    final priceTarget = _targetMode == 'PRICE'
        ? (double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0)
        : 0.0;
    final literTarget = _targetMode == 'LITER'
        ? (double.tryParse(_literController.text.replaceAll(',', '.')) ?? 0.0)
        : 0.0;
    final apiTargetValue = _targetMode == 'PRICE'
        ? priceTarget
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
        if (_viaCoords.isNotEmpty) 'vias': _viaCoords,
        // 서버가 우회시간을 '내가 화면에서 본 경로'와 같은 엔진·같은 옵션으로 재게 한다.
        'route_key': _selectedRouteKey,
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
      // 한도 초과(429)면 "오늘은 여기까지" 팝업 — 비교(직접선택)도 AI 분석과 합산 한도.
      final rl = rateLimitMessage(e, feature: 'AI 주유소 추천');
      if (rl != null) {
        showAppDialog<void>(context,
            icon: Icons.schedule_rounded,
            title: '오늘은 여기까지!',
            message: rl,
            primaryLabel: '확인');
      } else {
        showAppToast(context, '비교 실패: $e', isError: true);
      }
    }
  }

  Future<void> _drawCompareResultMap(Map<String, dynamic> data) async {
    // 비교 결과 지도 그리기 (간단 버전)
    if (_mapController == null) return;

    // 브랜드 로고 캐시 완료 대기 — 첫 렌더에서 로고 없는 배지 방지 (_drawResultOnMap 과 동일)
    if (!_brandImagesCached) {
      await GasStationMapBadge.precacheBrandImages(context);
      _brandImagesCached = true;
    }

    await _mapController!.clearOverlays();

    // 경로 — 목적지 입력 경로와 동일 렌더(혼잡도 구간색)
    await _drawMainRoute('compare_route', _lastPathPoints, _lastPathSegments);

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

    // A, B 주유소 마커 — 서버 응답은 {station:{...}, detour_time_min, ...} 중첩 구조.
    // (기존엔 최상위에서 lat/lng 를 읽어 항상 null → 마커가 아예 안 찍히던 버그)
    final stAWrap = data['station_a'] is Map ? data['station_a'] as Map : null;
    final stBWrap = data['station_b'] is Map ? data['station_b'] as Map : null;
    final winner = data['comparison'] is Map
        ? (data['comparison'] as Map)['winner']?.toString()
        : null;

    final stPoints = <NLatLng>[];
    Future<void> addStationMarker(Map? wrap, String tag, bool isWin) async {
      if (wrap == null) return;
      // 중첩(station) 우선, 혹시 몰라 평면 구조도 지원.
      final st = wrap['station'] is Map
          ? Map<String, dynamic>.from(wrap['station'] as Map)
          : Map<String, dynamic>.from(wrap);
      final lat = st['lat'] is num ? (st['lat'] as num).toDouble() : null;
      final lng = st['lng'] is num ? (st['lng'] as num).toDouble() : null;
      if (lat == null || lng == null) return;
      final color = isWin ? const Color(0xFF3B82F6) : const Color(0xFF64748B);
      final p = st['price_won_per_liter'] is num
          ? (st['price_won_per_liter'] as num).round()
          : null;
      final label = p != null ? '$tag ${_wonFmt.format(p)}원' : tag;
      final marker = NMarker(
        id: 'compare_${tag.toLowerCase()}',
        position: NLatLng(lat, lng),
        icon: await GasStationMapBadge.overlayImage(
          context,
          label: label,
          brand: st['brand']?.toString(),
          stationName: st['name']?.toString(),
          borderColor: color,
          textColor: color,
          emphasizeBorder: isWin,
        ),
        anchor: const NPoint(0.5, 1.0),
      );
      // 탭 → AI 추천과 동일한 미니시트(이름/주소/리터당/우회) — wrap 이 altItem 과 같은 형태.
      marker.setOnTapListener((_) async {
        if (!await _tapGuard()) return; // 핀치 오탭 가드
        await _showStationMiniSheet(Map<String, dynamic>.from(wrap));
      });
      await _mapController!.addOverlay(marker);
      stPoints.add(NLatLng(lat, lng));
    }

    await addStationMarker(stAWrap, 'A', winner == 'station_a');
    await addStationMarker(stBWrap, 'B', winner == 'station_b');

    // 카메라 — 출발/목적지/두 주유소가 모두 보이게
    final pts = <NLatLng>[
      NLatLng(_lastStartLat, _lastStartLng),
      NLatLng(_destLat!, _destLng!),
      ...stPoints,
    ];
    final minLat = pts.map((p) => p.latitude).reduce(min);
    final maxLat = pts.map((p) => p.latitude).reduce(max);
    final minLng = pts.map((p) => p.longitude).reduce(min);
    final maxLng = pts.map((p) => p.longitude).reduce(max);
    await _mapController!.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds(
          southWest: NLatLng(minLat, minLng),
          northEast: NLatLng(maxLat, maxLng)),
      padding: const EdgeInsets.all(80),
    ));
  }

  void _showExitDialog() {
    // 뒤로가기 → 바로 종료 확인 다이얼로그 (home_screen 과 동일, 토스트 단계 제거).
    showExitConfirmDialog(context);
  }

  /// 서버 통합 랭킹(ranked 1·2위, additive 필드) → 기존 on_route/best_detour 프레임 치환.
  /// - on_route 슬롯 ← 1위(추천), best_detour 슬롯 ← 2위(차선), choice='on_route' 고정
  /// - card_mode='ranked' 로 결과 화면이 라벨(추천/차선)을 분기
  /// - 판정 박스는 ranked_comparison(1위 vs 2위 비용 분해)으로 교체
  /// ranked 없으면(구서버) 원본 그대로 — 앱·서버 어느 쪽이 먼저 배포돼도 안전.
  Map<String, dynamic> _applyRankedFrame(Map<String, dynamic> d) {
    final ranked = d['ranked'];
    if (ranked is! List || ranked.isEmpty) return d;
    Map<String, dynamic>? entry(int i) =>
        (i < ranked.length && ranked[i] is Map)
            ? Map<String, dynamic>.from(ranked[i] as Map)
            : null;
    final r1 = entry(0);
    if (r1 == null || r1['station'] is! Map) return d;
    final r2 = entry(1);

    // via_route 재사용 — ranked 항목에 없으면 같은 주유소의 기존 슬롯 것.
    Map<String, dynamic>? oldVia(String id) {
      for (final k in const ['on_route', 'best_detour']) {
        final o = d[k];
        if (o is Map &&
            o['station'] is Map &&
            (o['station'] as Map)['id']?.toString() == id &&
            o['via_route'] is Map) {
          return Map<String, dynamic>.from(o['via_route'] as Map);
        }
      }
      return null;
    }

    for (final r in [r1, if (r2 != null) r2]) {
      if (r['via_route'] == null) {
        final id = (r['station'] as Map)['id']?.toString() ?? '';
        final v = oldVia(id);
        if (v != null) r['via_route'] = v;
      }
    }

    // 2위 카드의 '연료 기준 절약' — 싼 쪽이 2위일 때만 양수(초록 라벨).
    final rc = d['ranked_comparison'];
    if (r2 != null && rc is Map) {
      final sv = rc['savings_won'];
      final fw = rc['detour_fuel_won'];
      if (rc['cheaper_rank'] == 2 && sv is num && fw is num) {
        r2['fuel_savings_won'] = (sv - fw).round();
        r2['detour_fuel_won'] = fw.round();
        r2['detour_extra_min'] = rc['detour_extra_min'];
      }
    }

    final out = Map<String, dynamic>.from(d);
    out['on_route'] = r1;
    out['best_detour'] = r2;
    final rec = d['recommendation'] is Map
        ? Map<String, dynamic>.from(d['recommendation'] as Map)
        : <String, dynamic>{};
    rec['choice'] = 'on_route'; // 1위 = primary 슬롯 (지도 주황 마커)
    rec['card_mode'] = 'ranked';
    rec['show_secondary'] = r2 != null;
    final dt = rec['decision_trace'] is Map
        ? Map<String, dynamic>.from(rec['decision_trace'] as Map)
        : <String, dynamic>{};
    if (rc is Map && r2 != null) {
      final cheaperName = rc['cheaper_rank'] == 1
          ? ((r1['station'] as Map)['name']?.toString() ?? '추천')
          : ((r2['station'] as Map)['name']?.toString() ?? '차선');
      dt['cost_analysis'] = {
        ...Map<String, dynamic>.from(rc),
        'subject': cheaperName,
      };
    } else {
      dt['cost_analysis'] = null; // 후보 1개뿐 — 판정 박스 숨김
    }
    rec['decision_trace'] = dt;
    out['recommendation'] = rec;
    return out;
  }

  // 커넥티드 차량(현대/기아/제네시스)에서 현재 상태를 불러와 게이지에 세팅.
  // EV: 배터리 %(soc) 직접 / 주유: 주행가능거리(DTE)로 잔량% 역산.
  Future<void> _fetchFromConnectedCar(bool isEv, VehicleProfile? v) async {
    if (_fetchingFromCar || v == null || !v.isConnected) return;
    setState(() => _fetchingFromCar = true);
    try {
      final st = await ConnectedService.status(
          brand: v.connectedBrand, carId: v.connectedCarId, isEv: isEv);
      if (!mounted) return;
      double? level;
      String detail = '';
      if (isEv && st.soc != null) {
        level = st.soc!.clamp(0.0, 100.0).toDouble();
        detail = '배터리 ${level.round()}%';
      } else if (st.dteKm != null) {
        final cap = isEv ? v.batteryCapacity : v.tankCapacity;
        final eff = isEv ? v.evEfficiency : v.efficiency;
        final full = cap * eff;
        if (full > 0)
          level = (st.dteKm! / full * 100).clamp(0.0, 100.0).toDouble();
        detail = '주행가능 ${st.dteKm}km';
      }
      if (level != null) {
        final lv = level;
        setState(() {
          _currentLevelPercent = lv;
          _lastCarSyncAt = DateTime.now();
        });
        Hive.box(AppConstants.settingsBox)
            .put(AppConstants.keyAiCurrentLevelPercent, lv);
        showAppToast(context, '차에서 불러왔어요 · $detail');
      } else {
        showAppToast(context, '차량 데이터를 가져오지 못했어요', isError: true);
      }
    } catch (e) {
      if (mounted)
        showAppToast(context, ConnectedService.errorMessage(e, '불러오기 실패'),
            isError: true);
    } finally {
      if (mounted) setState(() => _fetchingFromCar = false);
    }
  }

  void _showLevelEditSheet(
      {bool isEv = false,
      required double capacity,
      required double efficiency,
      double targetChargePercent = 80.0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 슬라이더 드래그가 시트 끌어내림(drag-to-dismiss)과 경합해 풀리는 것 방지. 닫기는 X 버튼.
      enableDrag: false,
      backgroundColor: isDark ? AppColors.darkBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LevelEditSheet(
        initialLevel: _currentLevelPercent,
        initialMode: _targetMode,
        priceController: _priceController,
        literController: _literController,
        isEv: isEv,
        capacity: capacity, // 선택 차량 용량(가스 L / EV kWh)
        efficiency: efficiency, // 선택 차량 효율(가스 km/L / EV km/kWh)
        initialTargetChargePercent: targetChargePercent, // EV 목표 충전 %
        onSave: (level, mode, targetCharge) {
          setState(() {
            _currentLevelPercent = level;
            _targetMode = mode;
          });
          final box = Hive.box(AppConstants.settingsBox);
          // 목표값(금액/리터)도 프로필에 저장 — 안 그러면 차량정보 화면에 목표가 반영 안 됨
          // (기존엔 level/mode만 저장돼 목표값이 누락됐음).
          double? targetValue;
          if (mode == 'PRICE') {
            targetValue =
                double.tryParse(_priceController.text.replaceAll(',', '.'));
          } else if (mode == 'LITER') {
            targetValue =
                double.tryParse(_literController.text.replaceAll(',', '.'));
          }
          _saveVehicleLevel(box,
              level: level,
              mode: mode,
              price: targetValue,
              targetChargePercent: isEv ? targetCharge : null);
          // 글로벌 fallback도 유지
          box.put(AppConstants.keyAiCurrentLevelPercent, level);
          box.put(AppConstants.keyAiTargetMode, mode);
          if (targetValue != null) {
            if (mode == 'PRICE')
              box.put(AppConstants.keyAiTargetValue, targetValue);
            if (mode == 'LITER')
              box.put(AppConstants.keyAiLiterTarget, targetValue);
          }
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 플로팅 알약 바가 가리는 높이 — 시트를 Padding 으로 바 위에 올린다.
    // (최소높이를 키우는 방식은 기존 animateTo 값들과 계속 충돌해 시트가 멎었다 → 폐기)
    final double navPad = floatingNavOverlayPx(context);
    final settings = ref.watch(settingsProvider);
    final canGasAnalysis = settings.vehicleType != VehicleType.ev;
    final canEvAnalysis = settings.vehicleType != VehicleType.gas;
    if ((_aiAnalysisType == 'gas' && !canGasAnalysis) ||
        (_aiAnalysisType == 'ev' && !canEvAnalysis)) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const AiOnboardingScreen()),
          );
          if (!mounted) return;
          // 온보딩 미완료 채 닫혔으면 홈 탭으로 — 흰 빈 화면 방치 방지.
          // 완료되면 aiOnboardingDone=true 라 자연스럽게 본 AI 화면으로 진행.
          final stillUndone = !ref.read(settingsProvider).aiOnboardingDone;
          if (stillUndone) {
            _onboardingPushed = false; // 다음 진입 시 재표시 가능하도록 리셋
            ref.read(bottomNavIndexProvider.notifier).state = 0;
          }
        });
      }
      return Scaffold(
          backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg);
    }

    final box = Hive.box(AppConstants.settingsBox);
    // 선택 차량 프로필 = 단일 소스. 글로벌 키(keyAiTankCapacity 등)는 '차량 없을 때만' fallback.
    // (글로벌 키는 가스/EV·다차량이 공유하는 단일 슬롯이라 프로필과 어긋났음 → 카드·계산 불일치 버그)
    final sv = _readSelectedVehicle(box);
    final fuelCode = sv?.fuelType ??
        (box.get(AppConstants.keyAiFuelType,
            defaultValue: FuelType.gasoline.code) as String);
    final tankCapacity = sv == null
        ? (box.get(AppConstants.keyAiTankCapacity, defaultValue: 55.0) as num)
            .toDouble()
        : (sv.isEV ? sv.batteryCapacity : sv.tankCapacity);
    final efficiency = sv == null
        ? (box.get(AppConstants.keyAiEfficiency, defaultValue: 12.5) as num)
            .toDouble()
        : (sv.isEV ? sv.evEfficiency : sv.efficiency);
    final fuelLabel = FuelType.fromCode(fuelCode).label;

    // 멀티 차량 — 선택된 차량 프로필
    VehicleProfile? selectedVehicle;
    {
      final selectedId =
          box.get(AppConstants.keyAiSelectedVehicleId) as String?;
      final rawVehicles = box.get(AppConstants.keyAiVehicles);
      if (rawVehicles != null && selectedId != null) {
        try {
          final List decoded = jsonDecode(rawVehicles as String);
          final all = decoded
              .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
              .toList();
          selectedVehicle = all.cast<VehicleProfile?>().firstWhere(
              (v) => v?.id == selectedId,
              orElse: () => all.isNotEmpty ? all.first : null);
        } catch (_) {}
      }
    }
    final isEvVehicle = selectedVehicle?.isEV ?? false;

    // 선택 차량에 따라 분석 타입 자동 동기화
    final expectedType = isEvVehicle ? 'ev' : 'gas';
    if (_aiAnalysisType != expectedType) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() {
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

    // 차량 전환 감지 → 잔량/목표를 해당 차량 프로필 기준으로 갱신.
    // 표시값(_currentLevelPercent/_targetMode)은 이 빌드에서 '즉시' 동기화한다.
    //   - postFrame 으로 미루면: ① 한 프레임 동안 이전 차량 % 가 새 차량에 섞여 보이고,
    //     ② 빠른 탭전환 시 늦게 발화한 콜백이 stale sv 로 현재값을 덮어써 영구 꼬임.
    //   - _lastSyncedVehicleId 와 _currentLevelPercent 를 같은 시점에 맞춰 desync 제거.
    if (selectedVehicle != null && selectedVehicle.id != _lastSyncedVehicleId) {
      final sv = selectedVehicle;
      _lastSyncedVehicleId = sv.id;
      _currentLevelPercent = sv.currentLevelPercent;
      _targetMode = sv.targetMode;
      // 컨트롤러 text 는 build 중 변경 위험 → postFrame 으로만(표시값과 무관).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _priceController.text = sv.targetValue.toStringAsFixed(0);
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

        // 0. 절약 카드 팝업이 떠 있으면 그것부터 닫는다 (형 제보: 확인 안 누르고
        //    뒤로가기 하면 팝업은 그대로인 채 뒤 화면이 닫혀버렸다).
        //    가장 위에 뜬 UI 가 뒤로가기를 먼저 먹는 게 상식적인 동작.
        if (_revealHeadline != null) {
          markHandled();
          setState(() {
            _revealHeadline = null;
            _revealCaption = null;
          });
          return;
        }

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
            _mapController?.clearOverlays(
                type: NOverlayType.multipartPathOverlay);
            _mapController?.clearOverlays(type: NOverlayType.marker);
            _drawResultOnMap(
              pathPoints: _lastPathPoints,
              pathSegments: _lastPathSegments,
              originLat: _lastStartLat,
              originLng: _lastStartLng,
              stLat: null,
              stLng: null,
              stName: '',
              destLat: _destLat!,
              destLng: _destLng!,
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
                ? (_lastResultData!['alternatives'] as List)
                    .whereType<Map<String, dynamic>>()
                    .toList()
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
            // ── 배경 지도 (캐시된 NaverMap — 제스처 격리) ──
            // RepaintBoundary 로 지도 레이어 격리 — 시트/오버레이 변화 시 지도 같이 repaint 안 함
            RepaintBoundary(child: _buildMap(isDark)),

            // ── 피커 모드: 가운데 핀 ──
            if (_isPickerMode)
              IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_pin,
                          size: 52, color: _pickingOrigin ? kPrimary : kDanger),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),

            // ── 피커 모드: 상단 힌트 ──
            if (_isPickerMode)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkMapOverlay : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isDark
                            ? Border.all(
                                color: AppColors.darkCardBorder, width: 1)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 12)
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_location_alt_rounded,
                            color: _pickingOrigin ? kPrimary : kDanger,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _pickingOrigin
                                ? '지도에서 출발지를 선택하세요'
                                : '지도에서 목적지를 선택하세요',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppColors.darkTextPrimary : null,
                            ),
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
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkMapOverlay : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isDark
                            ? Border.all(
                                color: AppColors.darkCardBorder, width: 1)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 16)
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  color: _pickingOrigin ? kPrimary : kDanger,
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _isReverseGeocoding
                                    ? Text('주소 확인 중...',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : const Color(0xFF999999),
                                        ))
                                    : Text(
                                        _pickerAddress ?? '지도를 드래그하세요',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? AppColors.darkTextPrimary
                                              : null,
                                        ),
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
                                    side: const BorderSide(
                                        color: Color(0xFFDDDDDD)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  child: Text('취소',
                                      style: TextStyle(
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : const Color(0xFF666666))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: (_pickerLatLng != null &&
                                          !_isReverseGeocoding)
                                      ? _confirmMapPick
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _pickingOrigin ? kPrimary : kDanger,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  child: const Text('이 위치로 설정',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
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
            // 직접선택 결과(_isCompareResultMode)도 결과 화면 — 검색창·경로칩이 남아
            // 결과 요약 헤더와 겹치던 버그 방지.
            if (!_isPickerMode &&
                !_isResultMode &&
                !_isEvResultMode &&
                !_isEvSelectMode &&
                !_isCompareResultMode)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 상단: 모드 세그먼트 컨트롤 + 차량 버튼
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 46,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkMapOverlay
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: isDark
                                      ? Border.all(
                                          color: AppColors.darkCardBorder,
                                          width: 1)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ModeSegment(
                                        icon: Icons.local_gas_station_rounded,
                                        label: 'AI 주유소 추천',
                                        active: !isEvVehicle,
                                        accent: kFuelAccent,
                                        onTap: () => _switchModeTo(ev: false),
                                      ),
                                    ),
                                    Expanded(
                                      child: ModeSegment(
                                        icon: Icons.bolt_rounded,
                                        label: 'AI 충전소 추천',
                                        active: isEvVehicle,
                                        accent: kEvAccent,
                                        onTap: () => _switchModeTo(ev: true),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const AiVehicleListScreen()));
                                setState(() {});
                              },
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkMapOverlay
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(11),
                                  border: isDark
                                      ? Border.all(
                                          color: AppColors.darkCardBorder,
                                          width: 1)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 8)
                                  ],
                                ),
                                child: Icon(
                                  Icons.directions_car_rounded,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : const Color(0xFF666666),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 경로 입력 카드
                        RouteCard(
                          originName: _originName,
                          destName: _destName,
                          viaNames: [
                            for (final v in _vias) (v['name'] ?? '').toString()
                          ],
                          currentLocationAddress: _currentLocationAddress,
                          onSwap: _swapOriginDest,
                          onTapOrigin: () => _showLocationSheet(isOrigin: true),
                          onTapDest: () => _showLocationSheet(isOrigin: false),
                          onTapVia: (i) => _showLocationSheet(
                              isOrigin: false, forVia: true, viaIndex: i),
                          onAddVia: _addPendingVia,
                          onClearVia: _removeVia,
                          onReorder: (o, n) =>
                              unawaited(_reorderRouteSlots(o, n)),
                          collapsed: _routeCardCollapsed,
                          onToggleCollapsed: () => setState(() {
                            _routeCardCollapsed = !_routeCardCollapsed;
                            // 사용자가 직접 조작했으면 자동 접기가 덮어쓰지 않게.
                            _panelsAutoCollapsed = true;
                          }),
                          onClearOrigin: () => setState(() {
                            _originName = null;
                            _originLat = null;
                            _originLng = null;
                            _routeAlts = null;
                            _routesDistinct = false;
                          }),
                          onClearDest: () => setState(() {
                            _destName = null;
                            _destLat = null;
                            _destLng = null;
                            _errorMessage = null;
                            _routeAlts = null;
                            _routesDistinct = false;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 일반 모드: 하단 패널 ──
            if (!_isPickerMode &&
                !_isResultMode &&
                !_isEvResultMode &&
                !_isEvSelectMode &&
                !_isSelectMode &&
                !_isCompareResultMode)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 현재 위치 버튼 — 카드 바로 위에 자연스럽게 위치 (우측 정렬)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildMyLocationFab(),
                          ),
                        ),
                        // 에러 메시지
                        if (_errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kDanger.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: kDanger, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_errorMessage!,
                                      style: const TextStyle(
                                          fontSize: 12, color: kDanger)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ─── 접기 핸들 + HeroCard (네이버처럼 접어 지도 확보) ───
                        // 펼침 상태에선 핸들을 HeroCard 안 최상단(topHandle)으로 넣어 한 덩어리로.
                        // 접힘 요약 바 위에선 카드 밖 핸들 유지.
                        if (_heroCollapsed) _buildHeroToggleHandle(onMap: true),
                        if (_heroCollapsed)
                          _buildCollapsedHeroBar(
                            isEv: isEvVehicle,
                            level: _currentLevelPercent,
                            vehicleName:
                                selectedVehicle?.name.isNotEmpty == true
                                    ? selectedVehicle!.name
                                    : (isEvVehicle ? '차량 선택' : fuelLabel),
                            reachableKm: _currentLevelPercent /
                                100 *
                                (isEvVehicle
                                    ? (selectedVehicle?.batteryCapacity ??
                                        tankCapacity)
                                    : tankCapacity) *
                                (isEvVehicle
                                    ? (selectedVehicle?.evEfficiency ??
                                        efficiency)
                                    : efficiency),
                          )
                        else
                          HeroCard(
                            topHandle: _buildHeroToggleHandle(),
                            routeDistanceKm: _destRouteDistanceKm(),
                            isConnected: selectedVehicle?.isConnected ?? false,
                            isFetching: _fetchingFromCar,
                            lastSyncedAt: _lastCarSyncAt,
                            onFetchFromCar: () => _fetchFromConnectedCar(
                                isEvVehicle, selectedVehicle),
                            currentLevel: _currentLevelPercent,
                            isEv: isEvVehicle,
                            reachableKm: _currentLevelPercent /
                                100 *
                                (isEvVehicle
                                    ? (selectedVehicle?.batteryCapacity ??
                                        tankCapacity)
                                    : tankCapacity) *
                                (isEvVehicle
                                    ? (selectedVehicle?.evEfficiency ??
                                        efficiency)
                                    : efficiency),
                            vehicleName:
                                selectedVehicle?.name.isNotEmpty == true
                                    ? selectedVehicle!.name
                                    : (isEvVehicle ? '차량 선택' : fuelLabel),
                            efficiency: isEvVehicle
                                ? (selectedVehicle?.evEfficiency ?? efficiency)
                                : efficiency,
                            tankCapacity: isEvVehicle
                                ? (selectedVehicle?.batteryCapacity ??
                                    tankCapacity)
                                : tankCapacity,
                            // 유종 배지 — 주유 차량만. 선택 차량 프로필 유종 우선(fuelLabel).
                            fuelTypeLabel: isEvVehicle ? null : fuelLabel,
                            highwayOnly:
                                isEvVehicle ? _evHighwayOnly : _gasHighwayOnly,
                            chargerMode: isEvVehicle ? _evChargerType : null,
                            onTapLevel: () => _showLevelEditSheet(
                              isEv: isEvVehicle,
                              // 카드 표시와 동일한 차량 기준 용량/효율 (편집 시트 % 계산 일치)
                              capacity: isEvVehicle
                                  ? (selectedVehicle?.batteryCapacity ??
                                      tankCapacity)
                                  : tankCapacity,
                              efficiency: isEvVehicle
                                  ? (selectedVehicle?.evEfficiency ??
                                      efficiency)
                                  : efficiency,
                              targetChargePercent:
                                  selectedVehicle?.targetChargePercent ?? 80.0,
                            ),
                            // 편집 아이콘 → 현재 차량 setup(편집) 화면 직접 진입.
                            // 차량 미등록(selectedVehicle==null) 시에만 신규 추가 모드로.
                            onTapVehicle: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => selectedVehicle != null
                                      ? AiVehicleSetupScreen(
                                          editVehicleId: selectedVehicle.id)
                                      : const AiVehicleSetupScreen(),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                            onToggleHighway: () => setState(() {
                              final box = Hive.box(AppConstants.settingsBox);
                              if (isEvVehicle) {
                                _evHighwayOnly = !_evHighwayOnly;
                                box.put(_kEvHighwayKey, _evHighwayOnly);
                              } else {
                                _gasHighwayOnly = !_gasHighwayOnly;
                                box.put(_kGasHighwayKey, _gasHighwayOnly);
                              }
                            }),
                            onChangeChargerMode: isEvVehicle
                                ? (m) {
                                    setState(() => _evChargerType = m);
                                    _saveAiFilters();
                                  }
                                : null,
                            fastOutputs: _evFastOutputs,
                            onToggleFastOutput:
                                isEvVehicle ? _toggleEvFastOutput : null,
                            preferredBrands: _preferredGasBrands,
                            onToggleBrand: (k) {
                              setState(() {
                                if (!_preferredGasBrands.remove(k)) {
                                  _preferredGasBrands.add(k);
                                }
                              });
                              _saveAiFilters();
                            },
                            operatorCount: _preferredEvOperators.length +
                                _preferredEvBrands.length,
                            operatorSummary: () {
                              final tokens = <String>[
                                ..._preferredEvOperators,
                                ..._preferredEvBrands.map(evBrandLabel),
                              ];
                              return tokens.length <= 2
                                  ? tokens.join(', ')
                                  : '${tokens.take(2).join(', ')} 외 ${tokens.length - 2}';
                            }(),
                            onTapOperators: _openEvOperatorSheet,
                            socConditionSummary: _socConditionSummary,
                            socConditionCustom: _socConditionCustom,
                            onTapSocConditions:
                                isEvVehicle ? _openSocConditionSheet : null,
                          ),
                        _buildRouteSelector(isEv: isEvVehicle),
                        const SizedBox(height: 12),
                        // ─── HTML CTA row: gradient primary + 흰 secondary ───
                        Row(
                          children: [
                            // primary — AI 추천 (gradient + shadow)
                            Expanded(
                              flex: 13,
                              child: GestureDetector(
                                onTap: (_aiAnalyzing || _userSelecting)
                                    ? null
                                    : (isEvVehicle
                                        ? _runEvAnalyze
                                        : _runAnalyze),
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        modeAccentDeep(isEvVehicle),
                                        modeAccent(isEvVehicle),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: modeAccent(isEvVehicle)
                                            .withValues(alpha: 0.30),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: _aiAnalyzing
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white))
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.auto_awesome_rounded,
                                                size: 18,
                                                color: Colors.white),
                                            const SizedBox(width: 8),
                                            Text(
                                              isEvVehicle
                                                  ? 'AI 충전소 추천'
                                                  : 'AI 주유소 추천',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // secondary — 직접 선택 (흰 + border)
                            Expanded(
                              flex: 10,
                              child: GestureDetector(
                                onTap: (_aiAnalyzing || _userSelecting)
                                    ? null
                                    : (isEvVehicle
                                        ? _runEvUserSelect
                                        : _runUserSelect),
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    // 다크: 주변은 전부 다크인데 혼자 순백이던 버튼
                                    color: isDark
                                        ? AppColors.darkSurface1
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: isDark
                                            ? AppColors.darkCardBorder
                                            : kLine,
                                        width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: _userSelecting
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: modeAccent(isEvVehicle)))
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                Icons
                                                    .format_list_bulleted_rounded,
                                                size: 16,
                                                color: isDark
                                                    ? AppColors.darkTextPrimary
                                                    : kInk),
                                            const SizedBox(width: 6),
                                            Text(
                                              '직접 선택',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? AppColors.darkTextPrimary
                                                    : kInk,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
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
            // 직접선택 결과(_isCompareResultMode)도 포함 — 없으면 iOS 에서 결과 화면을
            // 나갈 방법이 없음(하드웨어 back 부재).
            if (_isResultMode ||
                _isEvResultMode ||
                _isEvSelectMode ||
                _isCompareResultMode)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _clearResult,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkMapOverlay
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: isDark
                                  ? Border.all(
                                      color: AppColors.darkCardBorder, width: 1)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Icon(Icons.arrow_back_rounded,
                                size: 18,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : const Color(0xFF1a1a1a)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkMapOverlay
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: isDark
                                  ? Border.all(
                                      color: AppColors.darkCardBorder, width: 1)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Text(
                              _lastRouteSummary ?? '분석 결과',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : const Color(0xFF1a1a1a)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 시트 하단 틈 메움 — 시트가 바 위에서 끝나 그 아래로 지도가
            //    비쳐 보였다(형 제보). 시트 배경색 스트립으로 바닥까지 이어 보이게.
            if (((_isResultMode || _isCompareResultMode || _isEvResultMode) &&
                    _lastResultData != null) ||
                (_isEvSelectMode && _evSelectCandidates.isNotEmpty) ||
                (_isSelectMode &&
                    _isSelectSheetVisible &&
                    _selectableStations != null))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: navPad,
                child: ColoredBox(
                    color: isDark ? AppColors.darkBg : Colors.white),
              ),

            // ── 결과 모드: 드래그 가능한 분석 결과 패널 ──
            if ((_isResultMode || _isCompareResultMode || _isEvResultMode) &&
                _lastResultData != null)
              Padding(
                padding: EdgeInsets.only(bottom: navPad),
                child: DraggableScrollableSheet(
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
                        color: isDark ? AppColors.darkBg : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: _isEvResultMode
                          ? EvResultBody(
                              key: _evResultBodyKey,
                              data: _lastResultData!,
                              scrollController: sc,
                              onStationMapTap: _showEvStationRouteOnMap,
                            onClearBrandFilter: () {
                              setState(() => _preferredEvBrands.clear());
                              _saveAiFilters();
                              _runEvAnalyze(); // 해제 즉시 재추천 — 한 탭 회복
                            },
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
              ),

            // ── EV 충전소 선택 모드: 하단 리스트 시트 ──
            if (_isEvSelectMode && _evSelectCandidates.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: navPad),
                child: DraggableScrollableSheet(
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
                        color: isDark ? AppColors.darkBg : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, -2))
                        ],
                      ),
                      child: EvSelectList(
                        candidates: _evSelectCandidates,
                        chargerType: _evChargerType,
                        speedRelaxed: _evSelectSpeedRelaxed,
                        scrollController: sc,
                        onSelect: _openEvStationDetail,
                      ),
                    );
                  },
                ),
              ),

            // ── 현재위치 버튼 (결과 모드: 시트 위에 붙어 이동) ──
            if (_isResultMode ||
                _isEvResultMode ||
                _isEvSelectMode ||
                _isSelectMode ||
                _isCompareResultMode)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom +
                    MediaQuery.of(context).size.height * _sheetSize +
                    12,
                child: GestureDetector(
                  onTap: _moveToMyLocation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_isLocating || _isAtMyLocation)
                          ? kPrimary
                          : (isDark ? AppColors.darkMapOverlay : Colors.white),
                      shape: BoxShape.circle,
                      border: isDark && !(_isLocating || _isAtMyLocation)
                          ? Border.all(
                              color: AppColors.darkCardBorder, width: 1)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
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
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : const Color(0xFF666666))),
                  ),
                ),
              ),

            // ── 사용자 선택 모드: 인라인 드래그 가능 시트 ──
            if (_isSelectMode &&
                _isSelectSheetVisible &&
                _selectableStations != null)
              Padding(
                padding: EdgeInsets.only(bottom: navPad),
                child: DraggableScrollableSheet(
                  controller: _selectSheetCtrl,
                  // 0.45 는 고정 영역(핸들+헤더+배너+버튼)을 빼면 카드 1개만 보였다
                  // (2026-08-16 제보 "20곳인데 1개") → 3개쯤 보이게 0.62.
                  initialChildSize: 0.62,
                  minChildSize: 0.14,
                  maxChildSize: 0.88,
                  snap: true,
                  snapSizes: const [0.14, 0.62, 0.88],
                  builder: (_, sc) => StationSelectInlineSheet(
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
              ),

            // ── AI 경로 추천 로딩 오버레이 ──
            if (_aiAnalyzing)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.18),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppColors.darkMapOverlay : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: isDark
                              ? Border.all(
                                  color: AppColors.darkCardBorder, width: 1)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
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
                                color: modeAccent(_aiAnalysisType == 'ev'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _aiAnalysisType == 'ev'
                                  ? 'AI 충전소 추천 중...'
                                  : 'AI 주유소 추천 중...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : const Color(0xFF1a1a1a),
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
                    color: Colors.black.withValues(alpha: 0.18),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppColors.darkMapOverlay : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: isDark
                              ? Border.all(
                                  color: AppColors.darkCardBorder, width: 1)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
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
                                color: kCompareBlue,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              _userSelectingMessage,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : const Color(0xFF1a1a1a),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── "이만큼 절약" 보상풍 오버레이 — 결과 도착 순간 최상단에서 1회 팝 ──
            if (_revealHeadline != null)
              SavingsRevealOverlay(
                key: ValueKey('savings_reveal_$_savingsRevealSeq'),
                caption: _revealCaption ?? '',
                headline: _revealHeadline!,
                stationName: _revealStationName,
                stationSub: _revealStationSub,
                stationIcon: _revealStationIcon,
                facts: _revealFacts,
                // 충전 추천이면 초록, 주유면 파랑 (아이콘으로 판정 — 호출부 공통)
                isEv: _revealStationIcon == Icons.ev_station_rounded,
                verdict: _revealVerdict,
                originName: _originName ?? _currentLocationAddress,
                destName: _destName,
                myUnitWon: _revealMyUnitWon,
                avgUnitWon: _revealAvgUnitWon,
                // [확인] = 닫기만 — 뒤의 AI 추천 결과 화면이 바로 보인다
                // (형 정정: 상세화면으로 튕기지 말 것).
              ),
          ],
        ),
      ), // Scaffold
    ); // PopScope
  }
}

// ─── 사용자 선택 인라인 시트 ────────────────────────────────────────────────────

// ─── 핵심 메트릭 셀 (이용가능 / 거리 / 도착 / 우회 4-cell 그리드) ───
/// 경로 화살표 — 네이버 스타일 얇은 chevron (위쪽 기본, angle 으로 방향 회전)
