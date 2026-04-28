import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/api_constants.dart';
import '../data/models/models.dart';
import '../data/services/api_service.dart';
import '../data/services/favorite_service.dart';
import '../data/services/location_service.dart';
import '../data/services/widget_service.dart';

/// 두 좌표 사이 거리(m) — 즐겨찾기처럼 distance가 서버에서 안 내려오는 경우
/// 사용자 현재 위치로 클라이언트에서 보정해서 표시.
double _haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

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
  final bool aiOnboardingDone;
  final VehicleType vehicleType;
  final FuelType fuelType;
  final List<String> chargerTypes;
  final int radius;
  final int defaultTab;

  const SettingsState({
    this.onboardingDone = false,
    this.aiOnboardingDone = false,
    this.vehicleType = VehicleType.gas,
    this.fuelType = FuelType.gasoline,
    this.chargerTypes = const ['01', '04'],
    this.radius = 5000,
    this.defaultTab = 0,
  });

  SettingsState copyWith({
    bool? onboardingDone, bool? aiOnboardingDone, VehicleType? vehicleType, FuelType? fuelType,
    List<String>? chargerTypes, int? radius, int? defaultTab,
  }) {
    return SettingsState(
      onboardingDone: onboardingDone ?? this.onboardingDone,
      aiOnboardingDone: aiOnboardingDone ?? this.aiOnboardingDone,
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
      aiOnboardingDone: _box.get(AppConstants.keyAiOnboardingDone, defaultValue: false),
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

  void completeAiOnboarding() {
    state = state.copyWith(aiOnboardingDone: true);
    _box.put(AppConstants.keyAiOnboardingDone, true);
  }
}

// ─── Active Tab Provider ───
final activeTabProvider = StateProvider<int>((ref) {
  final settings = ref.read(settingsProvider);
  // 홈탭 순서 바꾼 경우: 첫 번째 위치에 표시되는 탭을 기본 활성으로
  final tabOrder = Hive.box(AppConstants.settingsBox).get(AppConstants.keyHomeTabOrder, defaultValue: 0) as int;
  // tabOrder == 0: [주유, 충전] → defaultTab 그대로
  // tabOrder == 1: [충전, 주유] → 충전(1)이 앞에 오므로 활성 = 1
  if (tabOrder == 1 && settings.defaultTab == 0) return 1;
  if (tabOrder == 0 && settings.defaultTab == 1) return 0;
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

// ─── Favorites Provider ───
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<Map<String, dynamic>>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  FavoritesNotifier() : super(FavoriteService.getAll());

  void refresh() => state = FavoriteService.getAll();

  bool toggle({required String id, required String type, required String name, required String subtitle, Map<String, dynamic>? extra}) {
    final result = FavoriteService.toggle(id: id, type: type, name: name, subtitle: subtitle, extra: extra);
    state = FavoriteService.getAll();
    if (type == 'gas') {
      WidgetService.updateGasWidget();
    } else if (type == 'ev') {
      WidgetService.updateEvWidget();
    }
    return result;
  }
}

// chgerType 복합 타입을 단일 커넥터 코드로 확장
// 01=DC차데모, 02=AC완속, 03=DC차데모+AC3상, 04=DC콤보, 05=DC차데모+DC콤보
// 06=DC차데모+AC3상+DC콤보, 07=AC3상, 08=DC콤보(저속), 09=NACS, 89=H2(수소)
Set<String> _expandChargerType(String type) {
  switch (type) {
    case '03': return {'01', '07'};  // DC차데모 + AC3상
    case '05': return {'01', '04'};  // DC차데모 + DC콤보
    case '06': return {'01', '07', '04'};  // DC차데모 + AC3상 + DC콤보
    case '08': return {'04'};  // DC콤보(저속) → DC콤보로 매칭
    default: return {type};
  }
}

bool _chargerMatchesFilter(String chargerType, List<String> filterTypes) {
  final supported = _expandChargerType(chargerType);
  return filterTypes.any((t) => supported.contains(t));
}

// ─── 즐겨찾기 ID 기반 주유소 조회 (위치 무관) ───
// 단건 detail API는 유종을 모르면 가격이 0으로 떨어진다 → 현재 필터 유종 전달.
final favGasStationsProvider = FutureProvider<List<GasStation>>((ref) async {
  final favIds = ref.watch(favoritesProvider)
      .where((f) => f['type'] == 'gas')
      .map((f) => f['id'] as String)
      .toList();
  if (favIds.isEmpty) return [];
  final filter = ref.watch(gasFilterProvider);
  final fuelType = filter.fuelTypes.isNotEmpty ? filter.fuelTypes.first : 'B027';
  final results = await Future.wait(
    favIds.map((id) => ApiService()
        .getGasStationDetail(id, fuelType: fuelType)
        .catchError((_) => <String, dynamic>{})),
  );
  return results
      .where((json) => json.isNotEmpty)
      .map((json) {
        // detail API 응답에 brand 가 비어있는 경우(상위 Opinet API 필드 누락 등)
        // 즐겨찾기 등록 시 캐시한 brand 로 폴백 → 로고가 '기타'로 떨어지지 않게.
        final id = (json['id'] ?? json['UNI_ID'] ?? '').toString();
        final brandFromJson = (json['brand'] ?? json['POLL_DIV_CD'] ?? '').toString();
        if (id.isNotEmpty && brandFromJson.isEmpty) {
          final cached = FavoriteService.get(id, 'gas');
          final cachedBrand = (cached?['brand'] ?? '').toString();
          if (cachedBrand.isNotEmpty) {
            json = {...json, 'brand': cachedBrand};
          }
        }
        return GasStation.fromJson(json);
      })
      .toList();
});

// ─── 즐겨찾기 ID 기반 충전소 조회 (위치 무관) ───
final favEvStationsProvider = FutureProvider<List<EvStation>>((ref) async {
  final favIds = ref.watch(favoritesProvider)
      .where((f) => f['type'] == 'ev')
      .map((f) => f['id'] as String)
      .toList();
  if (favIds.isEmpty) return [];
  final results = await Future.wait(
    favIds.map((id) => ApiService().getEvStationDetail(id).catchError((_) => <String, dynamic>{})),
  );
  return results
      .where((json) => json.isNotEmpty)
      .map((json) => EvStation.fromJson(json['data'] ?? json))
      .toList();
});

// ─── Gas Stations Raw Provider (위치 기반 API, 필터·즐겨찾기 없음) ───
final gasStationsRawProvider = FutureProvider.family<List<GasStation>, ({double lat, double lng, int radius, List<String> fuelTypes})>(
  (ref, args) async {
    final results = await Future.wait(
      args.fuelTypes.map((ft) => ApiService().getGasStationsAround(
        lat: args.lat, lng: args.lng, radius: args.radius, fuelType: ft,
      )),
    );
    final seen = <String>{};
    final stations = <GasStation>[];
    for (final data in results) {
      for (final json in data) {
        final s = GasStation.fromJson(json);
        if (seen.add(s.id)) stations.add(s);
      }
    }
    return stations;
  },
);

// ─── Gas Stations Provider (즐겨찾기 항상 상단 + 필터 반응형) ───
final gasStationsProvider = Provider<AsyncValue<List<GasStation>>>((ref) {
  final location = ref.watch(locationProvider);
  final filter = ref.watch(gasFilterProvider);
  final favAsync = ref.watch(favGasStationsProvider);

  return location.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (loc) {
      if (loc == null) return const AsyncValue.data([]);
      final rawAsync = ref.watch(gasStationsRawProvider(
        (lat: loc.lat, lng: loc.lng, radius: filter.radius, fuelTypes: filter.fuelTypes),
      ));
      return rawAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, s) => AsyncValue.error(e, s),
        data: (raw) {
          // 즐겨찾기 로딩을 기다리지 않는다 — 위치 기반 결과를 먼저 그리고,
          // fav 도착 시 자연스럽게 상단에 끼어든다 (첫 진입 응답성 우선).
          final favRaw = favAsync.valueOrNull ?? [];
          // 상세 API는 distance를 안 돌려주므로 현재 위치 기반으로 재계산
          final favStations = favRaw
              .map((s) => s.copyWithDistance(_haversineM(loc.lat, loc.lng, s.lat, s.lng)))
              .toList()
            ..sort((a, b) => a.distance.compareTo(b.distance));
          final favIds = favStations.map((s) => s.id).toSet();
          // 위치 기반 결과에서 즐겨찾기 중복 제거
          var nonFavStations = raw.where((s) => !favIds.contains(s.id)).toList();

          if (filter.brands.isNotEmpty) {
            nonFavStations = nonFavStations.where((s) => filter.brands.contains(s.brand)).toList();
          }

          void sortGas(List<GasStation> list) {
            if (filter.sort == 2) {
              list.sort((a, b) => a.distance.compareTo(b.distance));
            } else {
              list.sort((a, b) => a.price.compareTo(b.price));
            }
          }
          sortGas(nonFavStations);
          return AsyncValue.data([...favStations, ...nonFavStations]);
        },
      );
    },
  );
});

// ─── EV Stations Raw Provider (위치 기반 API) ───
final evStationsRawProvider = FutureProvider.family<List<EvStation>, ({double lat, double lng, int radius})>(
  (ref, args) async {
    final results = await Future.wait([
      ApiService().getEvStationsAround(lat: args.lat, lng: args.lng, radius: args.radius),
      ApiService().getTeslaStationsAround(lat: args.lat, lng: args.lng, radius: args.radius),
    ]);
    return [
      ...results[0].map((json) => EvStation.fromJson(json)),
      ...results[1].map((json) => EvStation.fromJson(json)),
    ];
  },
);

// ─── EV Stations Provider (즐겨찾기 항상 상단 + 필터 반응형) ───
final evStationsProvider = Provider<AsyncValue<List<EvStation>>>((ref) {
  final location = ref.watch(locationProvider);
  final filter = ref.watch(evFilterProvider);
  final favAsync = ref.watch(favEvStationsProvider);

  return location.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (loc) {
      if (loc == null) return const AsyncValue.data([]);
      final rawAsync = ref.watch(evStationsRawProvider(
        (lat: loc.lat, lng: loc.lng, radius: filter.radius),
      ));
      return rawAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, s) => AsyncValue.error(e, s),
        data: (raw) {
          // 즐겨찾기 로딩을 기다리지 않는다 — 위치 기반 결과를 먼저 그리고,
          // fav 도착 시 자연스럽게 상단에 끼어든다 (첫 진입 응답성 우선).
          final favRaw = favAsync.valueOrNull ?? [];
          // 상세 API는 distance를 안 돌려주므로 현재 위치 기반으로 재계산
          final favStations = favRaw
              .map((s) => s.copyWithDistance(_haversineM(loc.lat, loc.lng, s.lat, s.lng)))
              .toList()
            ..sort((a, b) => (a.distance ?? double.infinity).compareTo(b.distance ?? double.infinity));
          final favIds = favStations.map((s) => s.statId).toSet();
          // 위치 기반 결과에서 즐겨찾기 중복 제거
          var nonFavStations = raw.where((s) => !favIds.contains(s.statId)).toList();

          if (filter.availableOnly) {
            nonFavStations = nonFavStations.where((s) => s.hasAvailable || s.isTesla).toList();
          }
          if (filter.chargerTypes.isNotEmpty) {
            nonFavStations = nonFavStations.where((s) =>
              s.chargers.any((c) => _chargerMatchesFilter(c.type, filter.chargerTypes))).toList();
          }
          if (filter.operators.isNotEmpty) {
            final includeOther = filter.operators.contains('__other__');
            final mainOps = filter.operators.where((o) => o != '__other__').toList();
            nonFavStations = nonFavStations.where((s) {
              if (mainOps.any((op) => s.operator.contains(op))) return true;
              if (includeOther && !['환경부','GS차지비','파워큐브','에버온','SK일렉링크','채비','Tesla']
                  .any((op) => s.operator.contains(op))) return true;
              return false;
            }).toList();
          }
          if (filter.kinds.isNotEmpty) {
            nonFavStations = nonFavStations.where((s) => filter.kinds.contains(s.kind)).toList();
          }

          int cmpPrice(int? a, int? b) {
            if (a == null && b == null) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            return a.compareTo(b);
          }
          void sortEv(List<EvStation> list) {
            if (filter.sort == 2) {
              list.sort((a, b) => cmpPrice(a.unitPriceFast ?? a.unitPriceSlow, b.unitPriceFast ?? b.unitPriceSlow));
            } else if (filter.sort == 3) {
              list.sort((a, b) => cmpPrice(a.unitPriceFastMember ?? a.unitPriceSlowMember, b.unitPriceFastMember ?? b.unitPriceSlowMember));
            }
          }
          sortEv(nonFavStations);
          return AsyncValue.data([...favStations, ...nonFavStations]);
        },
      );
    },
  );
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
    const validOptions = [1000, 3000, 5000];
    final validRadius = validOptions.contains(savedRadius) ? savedRadius : 5000;
    
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
