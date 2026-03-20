// ASCII/전각 괄호 안 한글(법인형태 등)을 유니코드 원문자로 치환
// 예: (주) → ㈜, (유) → ㈲  이유: 괄호는 라틴 폰트, 한글은 CJK 폰트가 혼합돼 굵기가 달라 보임
const _legalEntityMap = {
  '주': '㈜', '유': '㈲', '합': '㈳', '사': '㈷',
  '재': '㈶', '의': '㈷', '농': '㉩',
};

String _normalizeName(String name) => name.replaceAllMapped(
  RegExp(r'[（(]([가-힣]+)[）)]'),
  (m) => _legalEntityMap[m[1]] ?? m[0]!,
);

// ─── 주유소 모델 ───
class GasStation {
  final String id;
  final String name;
  final String brand;
  final String address;
  final double price;
  final double distance;
  final double lat;
  final double lng;
  final String? phone;
  final bool isSelf;
  final bool hasCarWash;
  final bool hasMaintenance;
  final String fuelType;

  GasStation({
    required this.id,
    required this.name,
    required this.brand,
    required this.address,
    required this.price,
    required this.distance,
    required this.lat,
    required this.lng,
    this.phone,
    this.isSelf = false,
    this.hasCarWash = false,
    this.hasMaintenance = false,
    this.fuelType = 'B027',
  });

  factory GasStation.fromJson(Map<String, dynamic> json) {
    return GasStation(
      id: json['UNI_ID'] ?? json['id'] ?? '',
      name: _normalizeName(json['OS_NM'] ?? json['name'] ?? ''),
      brand: json['POLL_DIV_CD'] ?? json['brand'] ?? '',
      address: json['NEW_ADR'] ?? json['address'] ?? '',
      price: (json['PRICE'] ?? json['price'] ?? 0).toDouble(),
      distance: (json['DISTANCE'] ?? json['distance'] ?? 0).toDouble(),
      lat: (json['GIS_Y_COOR'] ?? json['lat'] ?? 0).toDouble(),
      lng: (json['GIS_X_COOR'] ?? json['lng'] ?? 0).toDouble(),
      phone: json['TEL'] ?? json['phone'],
      isSelf: json['SELF_DIV_CD'] == 'Y' || json['isSelf'] == true,
      hasCarWash: json['CAR_WASH_YN'] == 'Y' || json['hasCarWash'] == true,
      hasMaintenance: json['MAINT_YN'] == 'Y' || json['hasMaintenance'] == true,
      fuelType: json['PROD_CD'] ?? json['fuelType'] ?? 'B027',
    );
  }

  String get brandName {
    switch (brand) {
      case 'SKE': return 'SK에너지';
      case 'GSC': return 'GS칼텍스';
      case 'HDO': return '현대오일뱅크';
      case 'SOL': return 'S-OIL';
      case 'RTO': return '알뜰주유소';
      case 'RTX': return '알뜰주유소';
      case 'NHO': return 'NH주유소';
      case 'ETC': return '기타';
      default: return brand;
    }
  }

  String get brandShort {
    switch (brand) {
      case 'SKE': return 'SK';
      case 'GSC': return 'GS';
      case 'HDO': return 'HD';
      case 'SOL': return 'S';
      case 'RTO': case 'RTX': return '알';
      case 'NHO': return 'NH';
      default: return brand.isNotEmpty ? brand[0] : '?';
    }
  }

  String get distanceText {
    if (distance < 1000) return '${distance.toInt()}m';
    return '${(distance / 1000).toStringAsFixed(1)}Km';
  }

  String get priceText => '${price.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';
}

// ─── 전기차 충전소 모델 ───
class EvStation {
  final String statId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String operator;
  final String? phone;
  final String useTime;
  final bool parkingFree;
  final List<Charger> chargers;
  final double? distance;
  final int? unitPriceFast;       // 급속 비회원
  final int? unitPriceSlow;       // 완속 비회원
  final int? unitPriceFastMember; // 급속 회원
  final int? unitPriceSlowMember; // 완속 회원
  final String? kind;
  final String? kindDetail;
  final bool isTesla;
  final String? stationType; // 'SC': 슈퍼차저, 'DT': 데스티네이션

  EvStation({
    required this.statId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.operator,
    this.phone,
    this.useTime = '24시간',
    this.parkingFree = false,
    this.chargers = const [],
    this.distance,
    this.unitPriceFast,
    this.unitPriceSlow,
    this.unitPriceFastMember,
    this.unitPriceSlowMember,
    this.kind,
    this.kindDetail,
    this.isTesla = false,
    this.stationType,
  });

  factory EvStation.fromJson(Map<String, dynamic> json) {
    final chargerList = (json['chargers'] as List<dynamic>?)
        ?.map((c) => Charger.fromJson(c as Map<String, dynamic>))
        .toList() ?? [];

    return EvStation(
      statId: json['statId'] ?? json['stat_id'] ?? '',
      name: json['statNm'] ?? json['name'] ?? '',
      address: json['addr'] ?? json['address'] ?? '',
      lat: (json['lat'] ?? 0).toDouble(),
      lng: (json['lng'] ?? 0).toDouble(),
      operator: json['busiNm'] ?? json['operator'] ?? '',
      phone: json['busiCall'] ?? json['phone'],
      useTime: json['useTime'] ?? '24시간',
      parkingFree: json['parkingFree'] == 'Y' || json['parkingFree'] == true,
      chargers: chargerList,
      distance: json['distance']?.toDouble(),
      unitPriceFast: json['unitPriceFast'] != null ? (json['unitPriceFast'] as num).toInt() : null,
      unitPriceSlow: json['unitPriceSlow'] != null ? (json['unitPriceSlow'] as num).toInt() : null,
      unitPriceFastMember: json['unitPriceFastMember'] != null ? (json['unitPriceFastMember'] as num).toInt() : null,
      unitPriceSlowMember: json['unitPriceSlowMember'] != null ? (json['unitPriceSlowMember'] as num).toInt() : null,
      kind: json['kind'],
      kindDetail: json['kindDetail'],
      isTesla: json['isTesla'] == true,
      stationType: json['stationType'],
    );
  }

  int get availableCount => chargers.where((c) => c.status == ChargerStatus.available).length;
  int get chargingCount => chargers.where((c) => c.status == ChargerStatus.charging).length;
  int get offlineCount => chargers.where((c) => c.status == ChargerStatus.commError || c.status == ChargerStatus.suspended || c.status == ChargerStatus.maintenance || c.status == ChargerStatus.unknown).length;
  int get totalCount => chargers.length;

  bool get hasAvailable => availableCount > 0;

  /// 비회원 요금 텍스트
  String? get priceNonMemberText {
    if (unitPriceFast != null && unitPriceSlow != null) return '비회원  급속 ${unitPriceFast} · 완속 ${unitPriceSlow}원';
    if (unitPriceFast != null) return '비회원  급속 ${unitPriceFast}원/kWh';
    if (unitPriceSlow != null) return '비회원  완속 ${unitPriceSlow}원/kWh';
    return null;
  }

  /// 회원 요금 텍스트
  String? get priceMemberText {
    if (unitPriceFastMember != null && unitPriceSlowMember != null) return '회원     급속 ${unitPriceFastMember} · 완속 ${unitPriceSlowMember}원';
    if (unitPriceFastMember != null) return '회원     급속 ${unitPriceFastMember}원/kWh';
    if (unitPriceSlowMember != null) return '회원     완속 ${unitPriceSlowMember}원/kWh';
    return null;
  }

  bool get hasPriceInfo => unitPriceFast != null || unitPriceSlow != null;

  String get distanceText {
    if (distance == null) return '';
    if (distance! < 1000) return '${distance!.toInt()}m';
    return '${(distance! / 1000).toStringAsFixed(1)}Km';
  }

  String? get maxPowerText {
    if (chargers.isEmpty) return null;
    final maxPower = chargers.map((c) => c.output).reduce((a, b) => a > b ? a : b);
    return '${maxPower}kW';
  }

  String get chargerTypeText {
    final types = chargers.map((c) => c.typeText).toSet().toList();
    return types.join(' · ');
  }
}

// ─── 충전기 모델 ───
class Charger {
  final String chgerId;
  final String type; // 01, 02, 03, 04, 05, 06, 07
  final int output; // kW
  final ChargerStatus status;
  final DateTime? chargingStarted; // nowTsdt: 현재 충전 시작 시각 (충전중일 때)
  final DateTime? lastChargeEnd;   // lastTedt: 마지막 충전 종료 시각
  final DateTime? lastStatusUpdate; // statUpdDt: 마지막 상태 업데이트 시각
  final int? unitPrice;

  Charger({
    required this.chgerId,
    required this.type,
    required this.output,
    required this.status,
    this.chargingStarted,
    this.lastChargeEnd,
    this.lastStatusUpdate,
    this.unitPrice,
  });

  static DateTime? _parseDt(String? raw) {
    if (raw == null || raw.length < 14) return null;
    return DateTime.tryParse(
      '${raw.substring(0,4)}-${raw.substring(4,6)}-${raw.substring(6,8)}T'
      '${raw.substring(8,10)}:${raw.substring(10,12)}:${raw.substring(12,14)}',
    );
  }

  factory Charger.fromJson(Map<String, dynamic> json) {
    return Charger(
      chgerId: json['chgerId'] ?? '',
      type: json['chgerType'] ?? '02',
      output: (json['output'] ?? 7).toInt(),
      status: ChargerStatus.fromCode(json['stat'] ?? 9),
      chargingStarted: _parseDt(json['nowTsdt']?.toString()),
      lastChargeEnd: _parseDt(json['lastTedt']?.toString()),
      lastStatusUpdate: _parseDt(json['statUpdDt']?.toString()),
      unitPrice: json['unitPrice'] != null ? (json['unitPrice'] as num).toInt() : null,
    );
  }

  String get typeText {
    switch (type) {
      case '01': return 'DC차데모';
      case '02': return 'AC완속';
      case '03': return 'DC차데모+AC3상';
      case '04': return 'DC콤보';
      case '05': return 'DC차데모+DC콤보';
      case '06': return 'DC차데모+AC3상+DC콤보';
      case '07': return 'AC3상';
      case '08': return 'DC콤보(저속)';
      case '09': return 'NACS';
      case '89': return 'H2(수소)';
      case 'SC': return '슈퍼차저';
      case 'DT': return '데스티네이션';
      default: return '기타';
    }
  }

  bool get isFast => output >= 50;
  bool get isUltraFast => output >= 100;
}

// ─── 충전기 상태 ───
enum ChargerStatus {
  commError,
  available,
  charging,
  suspended,
  maintenance,
  unknown;

  factory ChargerStatus.fromCode(dynamic code) {
    final c = int.tryParse(code.toString()) ?? 9;
    switch (c) {
      case 1: return ChargerStatus.commError;
      case 2: return ChargerStatus.available;
      case 3: return ChargerStatus.charging;
      case 4: return ChargerStatus.suspended;
      case 5: return ChargerStatus.maintenance;
      default: return ChargerStatus.unknown;
    }
  }

  bool get isAvailable => this == ChargerStatus.available;
  bool get isCharging => this == ChargerStatus.charging;
  bool get isOffline => this == ChargerStatus.commError || this == ChargerStatus.suspended || this == ChargerStatus.maintenance;

  String get label {
    switch (this) {
      case ChargerStatus.available: return '이용가능';
      case ChargerStatus.charging: return '충전중';
      case ChargerStatus.commError: return '통신이상';
      case ChargerStatus.suspended: return '운영중지';
      case ChargerStatus.maintenance: return '점검중';
      case ChargerStatus.unknown: return '상태미확인';
    }
  }
}

// ─── 유종 타입 ───
enum FuelType {
  gasoline('B027', '휘발유'),
  premium('B034', '고급휘발유'),
  diesel('D047', '경유'),
  lpg('K015', 'LPG');

  final String code;
  final String label;
  const FuelType(this.code, this.label);

  static FuelType fromCode(String code) {
    return FuelType.values.firstWhere((e) => e.code == code, orElse: () => FuelType.gasoline);
  }
}

// ─── 차량 타입 ───
enum VehicleType {
  gas('gas', '내연기관차'),
  ev('ev', '전기차'),
  both('both', '둘 다 사용');

  final String code;
  final String label;
  const VehicleType(this.code, this.label);

  static VehicleType fromCode(String code) {
    return VehicleType.values.firstWhere((e) => e.code == code, orElse: () => VehicleType.gas);
  }
}

// ─── 필터 옵션 ───
class GasFilterOptions {
  final int sort; // 1: 가격순, 2: 거리순
  final int radius;
  final List<String> fuelTypes;
  final List<String> brands;

  const GasFilterOptions({
    this.sort = 1,
    this.radius = 5000,
    this.fuelTypes = const ['B027'],
    this.brands = const [],
  });

  GasFilterOptions copyWith({int? sort, int? radius, List<String>? fuelTypes, List<String>? brands}) {
    return GasFilterOptions(
      sort: sort ?? this.sort,
      radius: radius ?? this.radius,
      fuelTypes: fuelTypes ?? this.fuelTypes,
      brands: brands ?? this.brands,
    );
  }
}

class EvFilterOptions {
  final int sort; // 1: 거리순, 2: 비회원가격순, 3: 회원가격순
  final int radius;
  final List<String> chargerTypes; // 빈 리스트 = 전체
  final bool availableOnly;
  final List<String> operators;
  final List<String> kinds; // 빈 리스트 = 전체 (A0~J0)

  const EvFilterOptions({
    this.sort = 1,
    this.radius = 5000,
    this.chargerTypes = const [],
    this.availableOnly = false,
    this.operators = const [],
    this.kinds = const [],
  });

  EvFilterOptions copyWith({
    int? sort, int? radius, List<String>? chargerTypes,
    bool? availableOnly, List<String>? operators, List<String>? kinds,
  }) {
    return EvFilterOptions(
      sort: sort ?? this.sort,
      radius: radius ?? this.radius,
      chargerTypes: chargerTypes ?? this.chargerTypes,
      availableOnly: availableOnly ?? this.availableOnly,
      operators: operators ?? this.operators,
      kinds: kinds ?? this.kinds,
    );
  }
}
