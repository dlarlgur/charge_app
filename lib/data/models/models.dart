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
  final bool isSel24; // 24시간 영업 (오피넷 isSel24)
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
    this.isSel24 = false,
    this.hasCarWash = false,
    this.hasMaintenance = false,
    this.fuelType = 'B027',
  });

  factory GasStation.fromJson(Map<String, dynamic> json) {
    return GasStation(
      id: json['UNI_ID'] ?? json['id'] ?? '',
      name: _normalizeName(json['display_name'] ?? json['OS_NM'] ?? json['name'] ?? ''),
      brand: json['POLL_DIV_CD'] ?? json['brand'] ?? '',
      address: json['NEW_ADR'] ?? json['address'] ?? '',
      price: (json['PRICE'] ?? json['price'] ?? 0).toDouble(),
      // 서버 가스 around: distance_m, OPINET 무료 API 시절: DISTANCE, 기타: distance
      distance: (json['DISTANCE'] ?? json['distance_m'] ?? json['distance'] ?? 0).toDouble(),
      lat: (json['GIS_Y_COOR'] ?? json['lat'] ?? 0).toDouble(),
      lng: (json['GIS_X_COOR'] ?? json['lng'] ?? 0).toDouble(),
      phone: json['TEL'] ?? json['phone'],
      isSelf: json['SELF_DIV_CD'] == 'Y' || json['isSelf'] == true,
      isSel24: json['isSel24'] == true,
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

  GasStation copyWithDistance(double newDistance) => GasStation(
    id: id,
    name: name,
    brand: brand,
    address: address,
    price: price,
    distance: newDistance,
    lat: lat,
    lng: lng,
    phone: phone,
    isSelf: isSelf,
    isSel24: isSel24,
    hasCarWash: hasCarWash,
    hasMaintenance: hasMaintenance,
    fuelType: fuelType,
  );
}

// ─── 전기차 충전소 모델 ───

/// 요금 표기 — 고시가가 307.2 / 325.6 / 393.1 처럼 소수 한 자리라 반올림하면 안 된다.
/// 소수부가 없으면 정수로(295), 있으면 한 자리로(307.2).
String evPriceText(num v) {
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
}

/// 출력 구간별 회원 요금 한 줄. 서버가 그 충전소에 **실제 있는 구간만** 내려준다.
/// (구간이 1개뿐이면 회원가 줄과 같은 값이라 서버가 아예 안 보낸다)
class EvTierPrice {
  final double kw;      // 구간 하한 (3.5 / 7 / 11 / 14 / 30 / 50 / 100 / 200 / 350)
  final String label;   // '급속 100kW'
  final double member;  // 회원 단가 (원/kWh)
  final double? keco;   // 같은 구간의 환경부 회원카드(로밍) 단가 — 환경부 직영은 null
  final bool fast;      // 급속 여부 — chgerType 기준(출력 아님)

  const EvTierPrice({
    required this.kw,
    required this.label,
    required this.member,
    this.keco,
    required this.fast,
  });

  factory EvTierPrice.fromJson(Map<String, dynamic> j) => EvTierPrice(
        kw: (j['kw'] as num?)?.toDouble() ?? 0,
        label: j['label']?.toString() ?? '',
        member: (j['member'] as num?)?.toDouble() ?? 0,
        keco: (j['keco'] as num?)?.toDouble(),
        fast: j['fast'] == true,
      );

  String get priceText => evPriceText(member);
  String get kecoText => keco == null ? '-' : evPriceText(keco!);
}

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
  final String? busiId; // 사업자 코드 — 브랜드(E-pit) 판정용, 구서버 응답은 null
  final List<Charger> chargers;
  final double? distance;
  // 요금은 double — 고시가가 307.2 / 325.6 / 393.1 처럼 소수 한 자리다.
  // int 로 받던 동안 .round() 로 뭉개져서 348.4 가 348 로 보였다.
  final double? unitPriceFast;       // 급속 비회원
  final double? unitPriceSlow;       // 완속 비회원
  final double? unitPriceFastMember; // 급속 회원
  final double? unitPriceSlowMember; // 완속 회원
  final double? kecoRoamFast; // 환경부 회원카드(로밍) 급속 — 목록/상세 모두 제공
  final double? kecoRoamSlow; // 환경부 회원카드(로밍) 완속
  /// 출력 구간별 회원 요금. 구간이 2개 이상인 충전소에만 실려 온다(1개면 회원가 줄과 동일).
  final List<EvTierPrice> tierPrices;
  final String? kind;
  final String? kindDetail;
  final bool isTesla;
  final String? stationType; // 'SC': 슈퍼차저, 'DT': 데스티네이션
  final bool limitYn;
  final String? limitDetail;
  final String? note;
  final bool isRestricted;
  /// 'open' | 'partial' | 'restricted'
  final String accessLevel;
  /// 운영 종료가 확인된 충전소. 목록·지도·추천에서는 서버가 빼지만 상세는 막지 않는다
  /// (즐겨찾기·딥링크가 깨지므로) — 대신 이 플래그로 안내한다.
  final bool closed;
  final String? closedReason;

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
    this.busiId,
    this.chargers = const [],
    this.distance,
    this.unitPriceFast,
    this.unitPriceSlow,
    this.unitPriceFastMember,
    this.unitPriceSlowMember,
    this.kecoRoamFast,
    this.kecoRoamSlow,
    this.tierPrices = const [],
    this.kind,
    this.kindDetail,
    this.isTesla = false,
    this.stationType,
    this.limitYn = false,
    this.limitDetail,
    this.note,
    this.isRestricted = false,
    this.accessLevel = 'open',
    this.closed = false,
    this.closedReason,
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
      // busiNm 이 빈 문자열('')로 와도 '기타'로 떨어지지 않게 — 비어있지 않은 첫 값 사용.
      operator: [json['busiNm'], json['operator'], json['busiNmRaw']]
          .map((e) => e?.toString().trim() ?? '')
          .firstWhere((s) => s.isNotEmpty, orElse: () => ''),
      phone: json['busiCall'] ?? json['phone'],
      useTime: json['useTime'] ?? '24시간',
      parkingFree: json['parkingFree'] == 'Y' || json['parkingFree'] == true,
      busiId: json['busiId']?.toString(),
      chargers: chargerList,
      distance: json['distance']?.toDouble(),
      unitPriceFast: (json['unitPriceFast'] as num?)?.toDouble(),
      unitPriceSlow: (json['unitPriceSlow'] as num?)?.toDouble(),
      unitPriceFastMember: (json['unitPriceFastMember'] as num?)?.toDouble(),
      unitPriceSlowMember: (json['unitPriceSlowMember'] as num?)?.toDouble(),
      kecoRoamFast: (json['kecoRoamFast'] as num?)?.toDouble(),
      kecoRoamSlow: (json['kecoRoamSlow'] as num?)?.toDouble(),
      tierPrices: (json['tierPrices'] as List<dynamic>?)
              ?.map((t) => EvTierPrice.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
      kind: json['kind'],
      kindDetail: json['kindDetail'],
      isTesla: json['isTesla'] == true,
      stationType: json['stationType'],
      limitYn: json['limitYn'] == 'Y' || json['limitYn'] == true,
      limitDetail: json['limitDetail']?.toString().isNotEmpty == true ? json['limitDetail'] : null,
      note: json['note']?.toString().isNotEmpty == true ? json['note'] : null,
      isRestricted: json['isRestricted'] == true,
      accessLevel: (json['accessLevel'] as String?) ?? (json['isRestricted'] == true ? 'restricted' : 'open'),
      closed: json['closed'] == true,
      closedReason: json['closedReason']?.toString(),
    );
  }

  int get availableCount => chargers.where((c) => c.status == ChargerStatus.available).length;
  int get chargingCount => chargers.where((c) => c.status == ChargerStatus.charging).length;
  /// 이용 불가 수 — 미수신(stat=9)도 포함한다. 미수신 중에 실제로 충전이 되더라도
  /// 우리는 알 수 없으므로 '확인 안 되면 못 쓰는 것'으로 보수적으로 센다.
  int get offlineCount => chargers.where((c) => c.status == ChargerStatus.commError || c.status == ChargerStatus.suspended || c.status == ChargerStatus.maintenance || c.status == ChargerStatus.unknown).length;
  int get totalCount => chargers.length;

  bool get hasAvailable => availableCount > 0;

  /// 급속 충전기 보유 (출력 ≥40kW). chargers 없으면 급속요금 유무로 폴백.
  bool get hasFast => chargers.isNotEmpty
      ? chargers.any((c) => c.output >= 40)
      : unitPriceFast != null;

  /// 완속 충전기 보유 (출력 <40kW). chargers 없으면 완속요금 유무로 폴백.
  bool get hasSlow => chargers.isNotEmpty
      ? chargers.any((c) => c.output < 40)
      : unitPriceSlow != null;

  /// 비회원 요금 텍스트
  String? get priceNonMemberText {
    if (unitPriceFast != null && unitPriceSlow != null) return '비회원  급속 ${evPriceText(unitPriceFast!)} · 완속 ${evPriceText(unitPriceSlow!)}원';
    if (unitPriceFast != null) return '비회원  급속 ${evPriceText(unitPriceFast!)}원/kWh';
    if (unitPriceSlow != null) return '비회원  완속 ${evPriceText(unitPriceSlow!)}원/kWh';
    return null;
  }

  /// 회원 요금 텍스트
  String? get priceMemberText {
    if (unitPriceFastMember != null && unitPriceSlowMember != null) return '회원     급속 ${evPriceText(unitPriceFastMember!)} · 완속 ${evPriceText(unitPriceSlowMember!)}원';
    if (unitPriceFastMember != null) return '회원     급속 ${evPriceText(unitPriceFastMember!)}원/kWh';
    if (unitPriceSlowMember != null) return '회원     완속 ${evPriceText(unitPriceSlowMember!)}원/kWh';
    return null;
  }

  /// 요금 섹션을 그릴지 여부. 환경부 로밍가도 '아는 요금'이므로 포함한다 —
  /// 빼놨더니 운영사 요금표가 없는 9,359개 충전소가 환경부가를 알면서도
  /// "요금 정보가 제공되지 않아요"로 덮여 있었다.
  bool get hasPriceInfo =>
      unitPriceFast != null ||
      unitPriceSlow != null ||
      unitPriceFastMember != null ||
      unitPriceSlowMember != null ||
      kecoRoamFast != null ||
      kecoRoamSlow != null;

  String get distanceText {
    if (distance == null) return '';
    if (distance! < 1000) return '${distance!.toInt()}m';
    return '${(distance! / 1000).toStringAsFixed(1)}Km';
  }

  /// 카드 우측 상단의 파워 라벨.
  /// 급속(50kW+)이 하나라도 있으면 "급속 NkW"로 표시,
  /// 없으면 "완속 NkW".
  String? get maxPowerText {
    if (chargers.isEmpty) return null;
    final fast = chargers.where((c) => c.isFast).toList();
    if (fast.isNotEmpty) {
      final maxFast = fast.map((c) => c.output).reduce((a, b) => a > b ? a : b);
      return '급속 ${maxFast}kW';
    }
    final maxSlow = chargers.map((c) => c.output).reduce((a, b) => a > b ? a : b);
    return '완속 ${maxSlow}kW';
  }

  String get chargerTypeText {
    final types = chargers.map((c) => c.typeText).toSet().toList();
    return types.join(' · ');
  }

  // ⚠ 필드 추가 시 여기도 반드시 복사할 것 — 빠뜨리면 목록에 거리 붙이는 순간
  //   조용히 null 이 된다. 실제로 busiId(브랜드 판정)·kecoRoam(환경부 요금)이
  //   누락돼 있어 지도 경로로 연 충전소에서 값이 사라졌다.
  EvStation copyWithDistance(double newDistance) => EvStation(
    statId: statId,
    name: name,
    address: address,
    lat: lat,
    lng: lng,
    operator: operator,
    phone: phone,
    useTime: useTime,
    parkingFree: parkingFree,
    busiId: busiId,
    chargers: chargers,
    distance: newDistance,
    unitPriceFast: unitPriceFast,
    unitPriceSlow: unitPriceSlow,
    unitPriceFastMember: unitPriceFastMember,
    unitPriceSlowMember: unitPriceSlowMember,
    kecoRoamFast: kecoRoamFast,
    kecoRoamSlow: kecoRoamSlow,
    tierPrices: tierPrices,
    kind: kind,
    kindDetail: kindDetail,
    isTesla: isTesla,
    stationType: stationType,
    limitYn: limitYn,
    limitDetail: limitDetail,
    note: note,
    isRestricted: isRestricted,
    accessLevel: accessLevel,
    closed: closed,
    closedReason: closedReason,
  );
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
      case '10': return 'DC콤보+NACS';
      case '89': return 'H2(수소)';
      case 'SC': return '슈퍼차저';
      case 'DT': return '데스티네이션';
      default: return '기타';
    }
  }

  bool get isFast => output >= 50;
  bool get isUltraFast => output >= 100;

  /// kW 속도 구간 — 필터 칩(완속/50/100/200/300+)과 동일 정의.
  /// 서버가 output 미상을 7 로 기본 처리하므로 미상은 'slow' 로 접힘.
  String get speedBucket {
    if (output < 40) return 'slow';
    if (output < 100) return '50';
    if (output < 200) return '100';
    if (output < 300) return '200';
    return '300';
  }
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

/// 조회 유종 코드 → 라벨. 차량 유종 enum(FuelType)과 별개 축 — 필터/홈 토글처럼
/// '조회'만 하는 곳은 등유(C004) 등 enum 밖 코드도 다뤄야 해서 이걸 쓴다.
/// (fromCode 는 미지 코드를 휘발유로 폴백 → 등유 켰는데 '휘발유' 탭이 생기던 버그)
String fuelCodeLabel(String code) {
  switch (code) {
    case 'B027': return '휘발유';
    case 'B034': return '고급휘발유';
    case 'D047': return '경유';
    case 'K015': return 'LPG';
    case 'C004': return '등유';
    default: return code;
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

// ─── 차량 프로필 (멀티 차량 지원) ───
class VehicleProfile {
  final String id;
  final String name;        // 차량 별명 (필수)
  final String vehicleType; // 'gas' | 'ev'

  // 내연기관 전용
  final String fuelType;      // FuelType code
  final double tankCapacity;  // L
  final double efficiency;    // km/L

  // 전기차 전용
  final double batteryCapacity; // kWh
  final double evEfficiency;    // km/kWh (전비)

  // 공통
  final double currentLevelPercent;

  // 내연기관 목표
  final String targetMode;   // FULL | PRICE | LITER
  final double targetValue;  // 금액(원) or 리터

  // 전기차 목표
  final double targetChargePercent; // 목표 충전 %

  // 커넥티드 연동 (현대/기아/제네시스) — 빈값이면 미연동.
  final String connectedBrand;  // '' | 'hyundai' | 'kia' | 'genesis'
  final String connectedCarId;  // 연동 차량 식별자(car_id)
  final String connectedCarName; // 연동 차량 표시명(모델명, 예: 아이오닉 5)

  const VehicleProfile({
    required this.id,
    required this.vehicleType,
    this.name = '',
    this.fuelType = 'B027',
    this.tankCapacity = 55.0,
    this.efficiency = 12.5,
    this.batteryCapacity = 64.0,
    this.evEfficiency = 5.0,
    this.currentLevelPercent = 25.0,
    this.targetMode = 'FULL',
    this.targetValue = 50000.0,
    this.targetChargePercent = 80.0,
    this.connectedBrand = '',
    this.connectedCarId = '',
    this.connectedCarName = '',
  });

  bool get isEV => vehicleType == 'ev';
  bool get isGas => vehicleType == 'gas';
  // 커넥티드 연동 여부 — true 일 때만 게이지의 '차에서 불러오기' 노출.
  bool get isConnected => connectedBrand.isNotEmpty && connectedCarId.isNotEmpty;

  String get displayLabel {
    if (isEV) return '전기차';
    return FuelType.fromCode(fuelType).label;
  }

  String get typeLabel => isEV ? '전기차' : '내연기관차';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'vehicleType': vehicleType,
    'fuelType': fuelType,
    'tankCapacity': tankCapacity,
    'efficiency': efficiency,
    'batteryCapacity': batteryCapacity,
    'evEfficiency': evEfficiency,
    'currentLevelPercent': currentLevelPercent,
    'targetMode': targetMode,
    'targetValue': targetValue,
    'targetChargePercent': targetChargePercent,
    'connectedBrand': connectedBrand,
    'connectedCarId': connectedCarId,
    'connectedCarName': connectedCarName,
  };

  factory VehicleProfile.fromJson(Map<String, dynamic> json) => VehicleProfile(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    vehicleType: json['vehicleType']?.toString() ?? 'gas',
    fuelType: json['fuelType']?.toString() ?? 'B027',
    tankCapacity: (json['tankCapacity'] as num? ?? 55.0).toDouble(),
    efficiency: (json['efficiency'] as num? ?? 12.5).toDouble(),
    batteryCapacity: (json['batteryCapacity'] as num? ?? 64.0).toDouble(),
    evEfficiency: (json['evEfficiency'] as num? ?? 5.0).toDouble(),
    currentLevelPercent: (json['currentLevelPercent'] as num? ?? 25.0).toDouble(),
    targetMode: json['targetMode']?.toString() ?? 'FULL',
    targetValue: (json['targetValue'] as num? ?? 50000.0).toDouble(),
    targetChargePercent: (json['targetChargePercent'] as num? ?? 80.0).toDouble(),
    connectedBrand: json['connectedBrand']?.toString() ?? '',
    connectedCarId: json['connectedCarId']?.toString() ?? '',
    connectedCarName: json['connectedCarName']?.toString() ?? '',
  );

  VehicleProfile copyWith({
    String? name,
    String? vehicleType,
    String? fuelType,
    double? tankCapacity,
    double? efficiency,
    double? batteryCapacity,
    double? evEfficiency,
    double? currentLevelPercent,
    String? targetMode,
    double? targetValue,
    double? targetChargePercent,
    String? connectedBrand,
    String? connectedCarId,
    String? connectedCarName,
  }) => VehicleProfile(
    id: id,
    name: name ?? this.name,
    vehicleType: vehicleType ?? this.vehicleType,
    fuelType: fuelType ?? this.fuelType,
    tankCapacity: tankCapacity ?? this.tankCapacity,
    efficiency: efficiency ?? this.efficiency,
    batteryCapacity: batteryCapacity ?? this.batteryCapacity,
    evEfficiency: evEfficiency ?? this.evEfficiency,
    currentLevelPercent: currentLevelPercent ?? this.currentLevelPercent,
    targetMode: targetMode ?? this.targetMode,
    targetValue: targetValue ?? this.targetValue,
    targetChargePercent: targetChargePercent ?? this.targetChargePercent,
    connectedBrand: connectedBrand ?? this.connectedBrand,
    connectedCarId: connectedCarId ?? this.connectedCarId,
    connectedCarName: connectedCarName ?? this.connectedCarName,
  );
}

// ─── 필터 옵션 ───
class GasFilterOptions {
  final int sort; // 1: 가격순, 2: 거리순
  final int radius;
  final List<String> fuelTypes;
  final List<String> brands;
  final bool open24Only; // 24시간 영업 주유소만 (false = 전체)

  const GasFilterOptions({
    this.sort = 1,
    this.radius = 5000,
    this.fuelTypes = const ['B027'],
    this.brands = const [],
    this.open24Only = false,
  });

  GasFilterOptions copyWith(
      {int? sort, int? radius, List<String>? fuelTypes, List<String>? brands, bool? open24Only}) {
    return GasFilterOptions(
      sort: sort ?? this.sort,
      radius: radius ?? this.radius,
      fuelTypes: fuelTypes ?? this.fuelTypes,
      brands: brands ?? this.brands,
      open24Only: open24Only ?? this.open24Only,
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
  final List<String> accessLevels; // 'open'/'partial'/'restricted', 빈 리스트 = 전체
  final List<String> speeds; // kW 속도 구간 'slow'/'50'/'100'/'200'/'300', 빈 리스트 = 전체
  final List<String> brands; // 브랜드 충전소 BMW/EPIT/PORSCHE/AUDI/BENZ, 빈 리스트 = 전체

  const EvFilterOptions({
    this.sort = 1,
    this.radius = 5000,
    this.chargerTypes = const [],
    this.availableOnly = false,
    this.operators = const [],
    this.kinds = const [],
    this.accessLevels = const [],
    this.speeds = const [],
    this.brands = const [],
  });

  EvFilterOptions copyWith({
    int? sort, int? radius, List<String>? chargerTypes,
    bool? availableOnly, List<String>? operators, List<String>? kinds,
    List<String>? accessLevels, List<String>? speeds, List<String>? brands,
  }) {
    return EvFilterOptions(
      sort: sort ?? this.sort,
      radius: radius ?? this.radius,
      chargerTypes: chargerTypes ?? this.chargerTypes,
      availableOnly: availableOnly ?? this.availableOnly,
      operators: operators ?? this.operators,
      kinds: kinds ?? this.kinds,
      accessLevels: accessLevels ?? this.accessLevels,
      speeds: speeds ?? this.speeds,
      brands: brands ?? this.brands,
    );
  }
}
