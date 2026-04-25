class ApiConstants {
  ApiConstants._();

  // Node.js 프록시 서버 (개발 시 로컬, 배포 시 변경)
  static const baseUrl = 'https://charge.dksw4.com/api'; // 운영 서버
  // static const baseUrl = 'http://10.254.110.57:1024/api'; // 실기기 (로컬)
  // static const baseUrl = 'http://10.0.2.2:1024/api'; // Android 에뮬레이터

  // ─── 버전 ───
  static const appVersion = '/version';

  // ─── 주유소 (Gas) ───
  static const gasAround = '/stations/gas/around';
  static const gasDetail = '/stations/gas'; // + /:id
  static const gasAvgPrice = '/prices/gas/average';

  // ─── 충전소 (EV) ───
  static const evAround = '/stations/ev/around';
  static const evDetail = '/stations/ev'; // + /:id
  static const evAnalytics = '/ev/analytics'; // + /:statId

  // ─── 테슬라 (OCM) ───
  static const teslaAround = '/stations/tesla/around';
  static const teslaDetail = '/stations/tesla'; // + /:uuid

  // ─── 검색 ───
  static const searchPlaces = '/search/places';

  // ─── 지오코딩 ───
  static const reverseGeocode = '/geocode/reverse';

  // ─── 주변 POI ───
  static const poiNearby = '/poi/nearby';

  // ─── AI 추천 ───
  static const routeDriving = '/route/driving';
  static const refuelAnalyze = '/v1/refuel/analyze';
  static const refuelRouteStations = '/v1/refuel/route-stations';
  static const refuelCompare = '/v1/refuel/compare';
  static const evAiRecommend = '/stations/ev/ai-recommend';

  // ─── 오피넷 유종 코드 ───
  static const fuelCodeGasoline = 'B027';
  static const fuelCodePremium = 'B034';
  static const fuelCodeDiesel = 'D047';
  static const fuelCodeLpg = 'K015';

  // ─── 환경부 충전기 타입 코드 ───
  static const chargerDcCombo = '01';
  static const chargerDcChademo = '02';
  static const chargerDcBoth = '03';
  static const chargerAcSlow = '04';
  static const chargerDcComboAc3 = '05';
  static const chargerAc3Phase = '06';
  static const chargerSupercharger = '07';

  // ─── 충전기 상태 코드 ───
  static const statusCommError = 1;
  static const statusAvailable = 2;
  static const statusCharging = 3;
  static const statusSuspended = 4;
  static const statusMaintenance = 5;
  static const statusUnknown = 9;
}

class AppConstants {
  AppConstants._();

  static const appName = '모두의 주유충전';
  static const packageName = 'com.dksw.charge';  // Android: com.dksw.charge

  // 기본값
  static const defaultRadius = 5000; // 5km in meters
  static const defaultFuelType = 'B027'; // 휘발유
  static const defaultSort = 1; // 가격순

  // 반경 옵션 (미터) - 오피넷 API는 최대 5km까지만 지원
  static const radiusOptions = [1000, 3000, 5000];

  // Hive Box 이름
  static const settingsBox = 'settings';
  static const favoritesBox = 'favorites';

  // Settings Keys
  static const keyOnboardingDone = 'onboarding_done';
  static const keyVehicleType = 'vehicle_type'; // gas, ev, both
  static const keyFuelType = 'fuel_type';
  static const keyChargerTypes = 'charger_types'; // List<String>
  static const keyRadius = 'radius';
  static const keyThemeMode = 'theme_mode'; // system, light, dark
  static const keyDefaultTab = 'default_tab'; // 0=gas, 1=ev

  // Gas Filter Keys
  static const keyGasFilterSort = 'gas_filter_sort';
  static const keyGasFilterRadius = 'gas_filter_radius';
  static const keyGasFilterFuelTypes = 'gas_filter_fuel_types';
  static const keyGasFilterBrands = 'gas_filter_brands';

  // EV Filter Keys
  static const keyEvFilterSort = 'ev_filter_sort';
  static const keyEvFilterRadius = 'ev_filter_radius';
  static const keyEvFilterChargerTypes = 'ev_filter_charger_types';
  static const keyEvFilterAvailableOnly = 'ev_filter_available_only';
  static const keyEvFilterOperators = 'ev_filter_operators';
  static const keyEvFilterKinds = 'ev_filter_kinds';
  static const keyEvFilterHighwayDir = 'ev_filter_highway_dir';

  // Map Toggle Keys (둘다 모드일 때만 저장)
  static const keyMapShowGas = 'map_show_gas';
  static const keyMapShowEv = 'map_show_ev';

  // Search History Key (AI + 지도탭 공용, JSON 인코딩된 List<String>)
  static const keySearchHistory = 'search_history';

  // AI Onboarding / Analyze Keys
  static const keyAiOnboardingDone = 'ai_onboarding_done';
  static const keyAiFuelType = 'ai_fuel_type';
  static const keyAiTankCapacity = 'ai_tank_capacity';
  static const keyAiEfficiency = 'ai_efficiency';
  static const keyAiCurrentLevelPercent = 'ai_current_level_percent';
  static const keyAiTargetMode = 'ai_target_mode'; // FULL | PRICE | LITER
  static const keyAiTargetValue = 'ai_target_value';
  static const keyAiLiterTarget = 'ai_liter_target';

  // 멀티 차량 프로필
  static const keyAiVehicles = 'ai_vehicles';           // JSON List<VehicleProfile>
  static const keyAiSelectedVehicleId = 'ai_selected_vehicle_id'; // String

  static const keyHomeTabOrder = 'home_tab_order'; // 0=주유 먼저, 1=충전 먼저
}
