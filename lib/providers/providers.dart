import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/api_constants.dart';
import '../data/models/models.dart';
import '../data/services/api_service.dart';
import '../data/services/location_service.dart';

// ─── Theme Provider ───
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_loadTheme());

  static ThemeMode _loadTheme() {
    final box = Hive.box(AppConstants.settingsBox);
    final mode = box.get(AppConstants.keyThemeMode, defaultValue: 'light');
    switch (mode) {
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.light;
    }
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    final box = Hive.box(AppConstants.settingsBox);
    box.put(AppConstants.keyThemeMode, mode.name);
  }

  void toggle() {
    if (state == ThemeMode.dark) {
      setTheme(ThemeMode.light);
    } else {
      setTheme(ThemeMode.dark);
    }
  }
}

// ─── Settings Provider (Hive) ───
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final bool onboardingDone;
  final VehicleType vehicleType;
  final FuelType fuelType;
  final List<String> chargerTypes;
  final int radius;
  final int defaultTab;

  const SettingsState({
    this.onboardingDone = false,
    this.vehicleType = VehicleType.gas,
    this.fuelType = FuelType.gasoline,
    this.chargerTypes = const ['01', '04'],
    this.radius = 5000,
    this.defaultTab = 0,
  });

  SettingsState copyWith({
    bool? onboardingDone, VehicleType? vehicleType, FuelType? fuelType,
    List<String>? chargerTypes, int? radius, int? defaultTab,
  }) {
    return SettingsState(
      onboardingDone: onboardingDone ?? this.onboardingDone,
      vehicleType: vehicleType ?? this.vehicleType,
      fuelType: fuelType ?? this.fuelType,
      chargerTypes: chargerTypes ?? this.chargerTypes,
      radius: radius ?? this.radius,
      defaultTab: defaultTab ?? this.defaultTab,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final _box = Hive.box(AppConstants.settingsBox);

  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  void _load() {
    state = SettingsState(
      onboardingDone: _box.get(AppConstants.keyOnboardingDone, defaultValue: false),
      vehicleType: VehicleType.fromCode(_box.get(AppConstants.keyVehicleType, defaultValue: 'gas')),
      fuelType: FuelType.fromCode(_box.get(AppConstants.keyFuelType, defaultValue: 'B027')),
      chargerTypes: List<String>.from(_box.get(AppConstants.keyChargerTypes, defaultValue: ['01', '04'])),
      radius: _box.get(AppConstants.keyRadius, defaultValue: 5000),
      defaultTab: _box.get(AppConstants.keyDefaultTab, defaultValue: 0),
    );
  }

  void setVehicleType(VehicleType type) {
    state = state.copyWith(
      vehicleType: type,
      defaultTab: type == VehicleType.ev ? 1 : 0,
    );
    _box.put(AppConstants.keyVehicleType, type.code);
    _box.put(AppConstants.keyDefaultTab, state.defaultTab);
  }

  void setFuelType(FuelType type) {
    state = state.copyWith(fuelType: type);
    _box.put(AppConstants.keyFuelType, type.code);
  }

  void setChargerTypes(List<String> types) {
    state = state.copyWith(chargerTypes: types);
    _box.put(AppConstants.keyChargerTypes, types);
  }

  void setRadius(int radius) {
    state = state.copyWith(radius: radius);
    _box.put(AppConstants.keyRadius, radius);
  }

  void completeOnboarding() {
    state = state.copyWith(onboardingDone: true);
    _box.put(AppConstants.keyOnboardingDone, true);
  }
}

// ─── Active Tab Provider ───
final activeTabProvider = StateProvider<int>((ref) {
  final settings = ref.read(settingsProvider);
  return settings.defaultTab;
});

// ─── Location Provider ───
final locationProvider = FutureProvider<({double lat, double lng})?>((ref) async {
  final pos = await LocationService().getCurrentPosition();
  if (pos == null) return null;
  return (lat: pos.latitude, lng: pos.longitude);
});

/// 실시간 위치 스트림 — 30m 이상 이동 시 업데이트
final locationStreamProvider = StreamProvider<({double lat, double lng})>((ref) {
  return LocationService().getPositionStream().map((pos) => (lat: pos.latitude, lng: pos.longitude));
});

// chgerType 복합 타입을 단일 커넥터 코드로 확장
// 05: DC차데모+AC3상, 06: DC차데모+DC콤보, 07: DC차데모+AC3상+DC콤보
Set<String> _expandChargerType(String type) {
  switch (type) {
    case '05': return {'01', '04'};
    case '06': return {'01', '03'};
    case '07': return {'01', '03', '04'};
    default: return {type};
  }
}

bool _chargerMatchesFilter(String chargerType, List<String> filterTypes) {
  final supported = _expandChargerType(chargerType);
  return filterTypes.any((t) => supported.contains(t));
}

// ─── Gas Stations Provider ───
final gasStationsProvider = FutureProvider<List<GasStation>>((ref) async {
  final location = await ref.watch(locationProvider.future);
  if (location == null) return [];

  final filter = ref.watch(gasFilterProvider);

  // 유종별 병렬 호출 후 합치기 (중복 제거)
  final results = await Future.wait(
    filter.fuelTypes.map((ft) => ApiService().getGasStationsAround(
      lat: location.lat,
      lng: location.lng,
      radius: filter.radius,
      fuelType: ft,
    )),
  );

  final seen = <String>{};
  var stations = <GasStation>[];
  for (final data in results) {
    for (final json in data) {
      final s = GasStation.fromJson(json);
      if (seen.add(s.id)) stations.add(s);
    }
  }

  // 브랜드 필터 (클라이언트)
  if (filter.brands.isNotEmpty) {
    stations = stations.where((s) => filter.brands.contains(s.brand)).toList();
  }

  // 정렬
  if (filter.sort == 2) {
    stations.sort((a, b) => a.distance.compareTo(b.distance));
  } else {
    stations.sort((a, b) => a.price.compareTo(b.price));
  }

  return stations;
});

// ─── EV Stations Provider ───
final evStationsProvider = FutureProvider<List<EvStation>>((ref) async {
  final location = await ref.watch(locationProvider.future);
  if (location == null) return [];

  final filter = ref.watch(evFilterProvider);

  // EV + Tesla 동시 조회
  final results = await Future.wait([
    ApiService().getEvStationsAround(lat: location.lat, lng: location.lng, radius: filter.radius),
    ApiService().getTeslaStationsAround(lat: location.lat, lng: location.lng, radius: filter.radius),
  ]);

  var stations = [
    ...results[0].map((json) => EvStation.fromJson(json)),
    ...results[1].map((json) => EvStation.fromJson(json)),
  ];

  if (filter.availableOnly) {
    stations = stations.where((s) => s.hasAvailable || s.isTesla).toList();
  }
  if (filter.chargerTypes.isNotEmpty) {
    stations = stations.where((s) =>
      s.chargers.any((c) => _chargerMatchesFilter(c.type, filter.chargerTypes))).toList();
  }
  if (filter.operators.isNotEmpty) {
    final includeOther = filter.operators.contains('__other__');
    final mainOps = filter.operators.where((o) => o != '__other__').toList();
    stations = stations.where((s) {
      if (mainOps.any((op) => s.operator.contains(op))) return true;
      if (includeOther && !['환경부','GS차지비','파워큐브','에버온','SK일렉링크','채비','Tesla']
          .any((op) => s.operator.contains(op))) return true;
      return false;
    }).toList();
  }
  if (filter.kinds.isNotEmpty) {
    stations = stations.where((s) => filter.kinds.contains(s.kind)).toList();
  }

  int cmpPrice(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  if (filter.sort == 2) {
    stations.sort((a, b) => cmpPrice(
      a.unitPriceFast ?? a.unitPriceSlow,
      b.unitPriceFast ?? b.unitPriceSlow,
    ));
  } else if (filter.sort == 3) {
    stations.sort((a, b) => cmpPrice(
      a.unitPriceFastMember ?? a.unitPriceSlowMember,
      b.unitPriceFastMember ?? b.unitPriceSlowMember,
    ));
  }
  // sort == 1: 거리순 (서버에서 이미 정렬됨)

  return stations;
});

// ─── Gas Avg Price Provider ───
final gasAvgPriceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ApiService().getGasAvgPrice();
});

// ─── Bottom Nav Provider ───
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

// ─── 지도 전용 Provider ───
final mapCenterProvider = StateProvider<({double lat, double lng})?>((_) => null);
/// 지도에서 사용할 반경(m). 줌에 따라 '이 지역 검색' 시 설정됨.
final mapRadiusProvider = StateProvider<int>((_) => 5000);

final mapGasStationsProvider = FutureProvider<List<GasStation>>((ref) async {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return [];
  final filter = ref.watch(gasFilterProvider);
  final radius = ref.watch(mapRadiusProvider);

  final results = await Future.wait(
    filter.fuelTypes.map((ft) => ApiService().getGasStationsAround(
      lat: center.lat, lng: center.lng,
      radius: radius, fuelType: ft, sort: 2,
    )),
  );

  final seen = <String>{};
  var stations = <GasStation>[];
  for (final data in results) {
    for (final json in data) {
      final s = GasStation.fromJson(json);
      if (seen.add(s.id)) stations.add(s);
    }
  }

  if (filter.brands.isNotEmpty) {
    stations = stations.where((s) => filter.brands.contains(s.brand)).toList();
  }

  stations.sort((a, b) => a.distance.compareTo(b.distance));
  return stations;
});

final mapEvStationsProvider = FutureProvider<List<EvStation>>((ref) async {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return [];
  final filter = ref.watch(evFilterProvider);
  final radius = ref.watch(mapRadiusProvider);

  final results = await Future.wait([
    ApiService().getEvStationsAround(lat: center.lat, lng: center.lng, radius: radius),
    ApiService().getTeslaStationsAround(lat: center.lat, lng: center.lng, radius: radius),
  ]);

  var stations = [
    ...results[0].map((json) => EvStation.fromJson(json)),
    ...results[1].map((json) => EvStation.fromJson(json)),
  ];

  if (filter.availableOnly) {
    stations = stations.where((s) => s.hasAvailable || s.isTesla).toList();
  }
  if (filter.chargerTypes.isNotEmpty) {
    stations = stations.where((s) =>
      s.chargers.any((c) => _chargerMatchesFilter(c.type, filter.chargerTypes))).toList();
  }
  if (filter.operators.isNotEmpty) {
    final includeOther = filter.operators.contains('__other__');
    final mainOps = filter.operators.where((o) => o != '__other__').toList();
    stations = stations.where((s) {
      if (mainOps.any((op) => s.operator.contains(op))) return true;
      if (includeOther && !['환경부','GS차지비','파워큐브','에버온','SK일렉링크','채비','Tesla']
          .any((op) => s.operator.contains(op))) return true;
      return false;
    }).toList();
  }
  if (filter.kinds.isNotEmpty) {
    stations = stations.where((s) => filter.kinds.contains(s.kind)).toList();
  }

  return stations;
});

// ─── Gas Filter Provider ───
final gasFilterProvider = StateNotifierProvider<GasFilterNotifier, GasFilterOptions>((ref) {
  return GasFilterNotifier();
});

class GasFilterNotifier extends StateNotifier<GasFilterOptions> {
  final _box = Hive.box(AppConstants.settingsBox);

  GasFilterNotifier() : super(const GasFilterOptions()) {
    _load();
  }

  void _load() {
    final savedRadius = _box.get(AppConstants.keyGasFilterRadius, defaultValue: 5000) as int;
    // 저장된 반경이 유효하지 않으면 기본값(5000)으로 리셋
    final validRadius = AppConstants.radiusOptions.contains(savedRadius) ? savedRadius : 5000;
    
    state = GasFilterOptions(
      sort: _box.get(AppConstants.keyGasFilterSort, defaultValue: 1),
      radius: validRadius,
      fuelTypes: List<String>.from(_box.get(AppConstants.keyGasFilterFuelTypes, defaultValue: ['B027'])),
      brands: List<String>.from(_box.get(AppConstants.keyGasFilterBrands, defaultValue: [])),
    );
  }

  void update(GasFilterOptions options) {
    state = options;
    _box.put(AppConstants.keyGasFilterSort, options.sort);
    _box.put(AppConstants.keyGasFilterRadius, options.radius);
    _box.put(AppConstants.keyGasFilterFuelTypes, options.fuelTypes);
    _box.put(AppConstants.keyGasFilterBrands, options.brands);
  }
}

// ─── EV Filter Provider ───
final evFilterProvider = StateNotifierProvider<EvFilterNotifier, EvFilterOptions>((ref) {
  return EvFilterNotifier();
});

class EvFilterNotifier extends StateNotifier<EvFilterOptions> {
  final _box = Hive.box(AppConstants.settingsBox);

  EvFilterNotifier() : super(const EvFilterOptions()) {
    _load();
  }

  void _load() {
    state = EvFilterOptions(
      sort: _box.get(AppConstants.keyEvFilterSort, defaultValue: 1),
      radius: _box.get(AppConstants.keyEvFilterRadius, defaultValue: 5000),
      chargerTypes: List<String>.from(_box.get(AppConstants.keyEvFilterChargerTypes, defaultValue: [])),
      availableOnly: _box.get(AppConstants.keyEvFilterAvailableOnly, defaultValue: false),
      operators: List<String>.from(_box.get(AppConstants.keyEvFilterOperators, defaultValue: [])),
      kinds: List<String>.from(_box.get(AppConstants.keyEvFilterKinds, defaultValue: [])),
    );
  }

  void update(EvFilterOptions options) {
    state = options;
    _box.put(AppConstants.keyEvFilterSort, options.sort);
    _box.put(AppConstants.keyEvFilterRadius, options.radius);
    _box.put(AppConstants.keyEvFilterChargerTypes, options.chargerTypes);
    _box.put(AppConstants.keyEvFilterAvailableOnly, options.availableOnly);
    _box.put(AppConstants.keyEvFilterOperators, options.operators);
    _box.put(AppConstants.keyEvFilterKinds, options.kinds);
  }
}
