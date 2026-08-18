import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import 'ad_service.dart';
import 'auth_service.dart';

/// 응원 뱃지 등급 — 누적 응원 횟수 기준. 스포츠카 사다리 (형 아이디어):
/// 국산 쿠페급에서 시작해 하이퍼카까지. 실제 브랜드명은 상표 리스크라 급 이름만 쓴다.
class CheerBadge {
  final int level; // 0 = 아직 없음
  final String name;
  final int threshold; // 이 등급이 되는 누적 횟수

  const CheerBadge._(this.level, this.name, this.threshold);

  // 코드 기본값 — 서버 원격설정(cheer.tier_thresholds)이 오면 effectiveTiers 가 덮는다.
  static const tiers = [
    CheerBadge._(1, '쿠페 서포터', 1),
    CheerBadge._(2, '스포츠카 서포터', 10),
    CheerBadge._(3, '슈퍼카 서포터', 40),
    CheerBadge._(4, '하이퍼카 서포터', 120),
  ];

  static const none = CheerBadge._(0, '', 0);

  // 서버 임계값 override — status 응답에서 applyThresholds 로 반영, Hive 유지.
  // UI 쪽 CheerTierTheme 도 같은 키를 읽는다(양쪽 판정 일치 보장).
  static List<CheerBadge>? _overridden;
  static bool _loaded = false;
  static const hiveThresholdsKey = 'cheer_tier_thresholds';

  static List<CheerBadge> get effectiveTiers {
    if (!_loaded) {
      _loaded = true;
      try {
        final raw = Hive.box('settings').get(hiveThresholdsKey);
        if (raw is List) _applyList(raw.whereType<int>().toList(), persist: false);
      } catch (_) {}
    }
    return _overridden ?? tiers;
  }

  /// 서버 status 의 tierThresholds 반영 + Hive 저장. 형식이 깨져 있으면 무시.
  static void applyThresholds(List<int>? t) {
    if (t == null) return;
    _loaded = true;
    _applyList(t, persist: true);
  }

  static void _applyList(List<int> t, {required bool persist}) {
    if (t.length != tiers.length) return;
    for (var i = 0; i < t.length; i++) {
      if (t[i] <= 0 || (i > 0 && t[i] <= t[i - 1])) return;
    }
    _overridden = [
      for (var i = 0; i < tiers.length; i++)
        CheerBadge._(tiers[i].level, tiers[i].name, t[i]),
    ];
    if (persist) {
      try {
        Hive.box('settings').put(hiveThresholdsKey, t);
      } catch (_) {}
    }
  }

  /// 누적 횟수 → 현재 뱃지 (0회면 none)
  static CheerBadge of(int total) {
    CheerBadge cur = none;
    for (final t in effectiveTiers) {
      if (total >= t.threshold) cur = t;
    }
    return cur;
  }

  /// 다음 등급 (만땅이면 null)
  static CheerBadge? nextOf(int total) {
    for (final t in effectiveTiers) {
      if (total < t.threshold) return t;
    }
    return null;
  }
}

/// 월간 랭킹 이벤트(치킨 등) — 서버 원격설정으로 켜질 때만 내려온다.
/// 꺼져 있으면 status.event 가 null 이라 앱은 아무것도 그리지 않는다(앱 배포 불필요).
class CheerEvent {
  final String title;
  final String desc;
  final String reward;
  final String month;
  final int myCount;
  final int? myRank;
  final List<CheerEventRank> top;

  /// 1위까지 남은 응원 수 (내가 1위면 0, 비교 불가면 null)
  final int? chaseToTop;

  /// 바로 아래 순위와 벌린 차이 (순위표 밖이면 null)
  final int? chaseFromNext;

  const CheerEvent({
    required this.title,
    required this.desc,
    required this.reward,
    required this.month,
    required this.myCount,
    required this.myRank,
    required this.top,
    required this.chaseToTop,
    required this.chaseFromNext,
  });

  factory CheerEvent.fromJson(Map<String, dynamic> j) => CheerEvent(
        title: j['title']?.toString() ?? '이달의 응원왕 이벤트',
        desc: j['desc']?.toString() ?? '',
        reward: j['reward']?.toString() ?? '',
        month: j['month']?.toString() ?? '',
        myCount: (j['myCount'] as num?)?.toInt() ?? 0,
        myRank: (j['myRank'] as num?)?.toInt(),
        top: ((j['top'] as List?) ?? const [])
            .map((e) => CheerEventRank.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        chaseToTop: ((j['chase'] as Map?)?['toTop'] as num?)?.toInt(),
        chaseFromNext: ((j['chase'] as Map?)?['fromNext'] as num?)?.toInt(),
      );
}

/// 진행 중인 달의 순위 한 줄 — **횟수는 없다**.
/// 남의 응원 횟수는 서버가 아예 안 내려준다(형 지시). 격차는 CheerEvent.chase* 로만.
class CheerEventRank {
  final int rank;
  final String name;
  final bool me;
  const CheerEventRank(
      {required this.rank, required this.name, required this.me});

  factory CheerEventRank.fromJson(Map<String, dynamic> j) => CheerEventRank(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '익명의 서포터',
        me: j['me'] == true,
      );
}

/// 진행 중인 달의 '내 상황' 한 줄 — **등수 숫자를 쓰지 않는다**(형 지시).
///
/// "3위" 같은 등수는 하위권에겐 의욕만 꺾고 상위권은 안심시킨다. 대신 위·아래와
/// 몇 회 차이인지만 말해 오늘 한 번 더 볼 이유를 준다.
/// 남의 응원 횟수는 서버가 안 내려주므로 여기 쓰이는 값은 격차뿐이다.
String cheerChaseCopy(CheerEvent ev) {
  if (ev.myCount == 0) return '한 번만 응원해도 순위에 들어가요';
  final up = ev.chaseToTop;
  final down = ev.chaseFromNext;

  // 선두 — 등수 대신 '쫓기는 상황'을 말한다
  if (up != null && up == 0) {
    if (down == null) return '지금 선두를 달리고 있어요';
    if (down == 0) return '바로 뒤와 동점이에요 — 한 번이면 앞서요';
    if (down <= 3) return '바로 뒤가 $down회 차이로 쫓아오고 있어요';
    return '$down회 차이로 앞서고 있어요';
  }
  // 추격 중
  if (up != null) {
    if (up <= 3) return '1위까지 $up회 — 오늘 따라잡을 수 있어요';
    return '1위까지 $up회 남았어요';
  }
  return '이번 달 ${ev.myCount}회 응원했어요';
}

/// 'YYYY-MM' → '8월' (수상 pill·상장 문구용). 형식이 다르면 원문 그대로.
String cheerMonthLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final m = int.tryParse(parts[1]);
  return m == null ? month : '$m월';
}

/// 'YYYY-MM' → '2026년 8월'
String cheerMonthLabelFull(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final m = int.tryParse(parts[1]);
  return m == null ? month : '${parts[0]}년 $m월';
}

/// 월간 응원 왕관 — 매월 1일 서버가 지난달 1·2·3등을 확정한다.
class CheerCrown {
  final String month; // 'YYYY-MM'
  final int rank; // 1=금 2=은 3=동
  final int count;
  const CheerCrown({required this.month, required this.rank, required this.count});

  factory CheerCrown.fromJson(Map<String, dynamic> j) => CheerCrown(
        month: j['month']?.toString() ?? '',
        rank: (j['rank'] as num?)?.toInt() ?? 3,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// {'3': 'blue'} → {3: 'blue'} — 서버는 JSON 키 제약으로 문자열 등급을 준다.
/// 서버 carPaints 파싱. **null 과 {} 는 뜻이 다르다.**
///   {}   저장된 색이 없음(정상) → 첫 로그인 1회에 한해 로컬 값을 서버로 올린다
///   null 서버가 모름(조회 실패) → 아무것도 하지 않는다. 올리지도, 지우지도 않는다
/// 예전엔 둘 다 {} 로 접혀서, 서버 DB 가 삐끗한 순간 앱이 "저장 없음"으로 읽고
/// 로컬 값을 올려 계정 색을 덮어쓸 수 있었다.
Map<int, String>? parseCarPaints(dynamic raw) {
  if (raw is! Map) return null;
  final out = <int, String>{};
  raw.forEach((k, v) {
    final lv = int.tryParse(k.toString());
    if (lv != null && v is String && v.isNotEmpty) out[lv] = v;
  });
  return out;
}

/// 상품 수량 문구 — "치킨 2마리" / "커피 3개" / 1개면 라벨만.
/// 조사·단위를 서버가 안 주므로 라벨 기반 최소 규칙만 쓴다 (치킨=마리, 그 외=개).
String prizeQtyText(String label, int qty) {
  if (qty <= 1) return label;
  final unit = label.contains('치킨') ? '마리' : '개';
  return '$label $qty$unit';
}

/// 내 상품 (`/awards` my_prize) — 발표 open && 본인이 수령자일 때만 내려온다.
/// pos = 자리 순번 (동점 룰렛 서열 반영), 상품은 자리 기준.
class CheerPrize {
  final int pos;
  final String label;
  final int qty;
  const CheerPrize({required this.pos, required this.label, required this.qty});

  static CheerPrize? fromJson(dynamic j) {
    if (j is! Map) return null;
    final label = j['label']?.toString() ?? '';
    if (label.isEmpty) return null;
    return CheerPrize(
      pos: (j['pos'] as num?)?.toInt() ?? 0,
      label: label,
      qty: (j['qty'] as num?)?.toInt() ?? 1,
    );
  }

  String get text => prizeQtyText(label, qty);
}

/// 시상식 배너 문구 서버 주도 (`/awards` prize_banner) — null 이면 구서버,
/// 기존 chicken.on + 치킨 하드코딩 문구로 폴백한다 (회귀 금지).
class CheerPrizeBanner {
  final bool on;
  final String label;
  final int qty;
  const CheerPrizeBanner(
      {required this.on, required this.label, required this.qty});

  static CheerPrizeBanner? fromJson(dynamic j) {
    if (j is! Map) return null;
    final label = j['label']?.toString() ?? '';
    if (label.isEmpty) return null;
    return CheerPrizeBanner(
      on: j['on'] == true,
      label: label,
      qty: (j['qty'] as num?)?.toInt() ?? 1,
    );
  }

  String get text => prizeQtyText(label, qty);
}

/// 월간 시상식(결산) — GET /api/cheer/awards
class CheerAwards {
  final String month; // 'YYYY-MM'
  final int total; // 그 달 전체 응원 수
  final List<CheerAwardRank> top; // 1~3위
  final int? myRank;
  final int myCount;
  /// 전월 대비 순위 변동 (+면 상승). 비교 불가면 null
  final int? delta;
  /// 내가 그 달 1등인지 — 상장(시상식)은 1등만 본다
  final bool winner;
  final bool chickenOn;
  final bool chickenSent;

  /// 발송됐다면 그 소식함 항목 id — 배너를 누르면 목록이 아니라 상세로 바로 연다.
  final int? chickenInboxId;

  /// 발표 상태 — 'hold' | 'open' | 'unknown'(조회 실패) | null(행 없음/구서버).
  /// hold·unknown 은 왕관 소진 금지 게이트에 쓰인다 (2·3위 개인 축하).
  final String? broadcastStatus;

  /// 내 상품 — open && 본인 수령자일 때만. 1위 상장 상품 줄·2·3위 축하에 쓴다.
  final CheerPrize? myPrize;

  /// 배너 문구 서버 주도 — null 이면 chicken.on + 치킨 문구 폴백.
  final CheerPrizeBanner? prizeBanner;

  const CheerAwards({
    required this.month,
    required this.total,
    required this.top,
    required this.myRank,
    required this.myCount,
    required this.delta,
    required this.winner,
    required this.chickenOn,
    required this.chickenSent,
    this.chickenInboxId,
    this.broadcastStatus,
    this.myPrize,
    this.prizeBanner,
  });

  factory CheerAwards.fromJson(Map<String, dynamic> j) {
    final me = (j['me'] as Map?) ?? const {};
    final chicken = (j['chicken'] as Map?) ?? const {};
    return CheerAwards(
      month: j['month']?.toString() ?? '',
      total: (j['total'] as num?)?.toInt() ?? 0,
      top: ((j['top'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CheerAwardRank.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      myRank: (me['rank'] as num?)?.toInt(),
      myCount: (me['count'] as num?)?.toInt() ?? 0,
      delta: (me['delta'] as num?)?.toInt(),
      winner: j['winner'] == true,
      chickenOn: chicken['on'] == true,
      chickenSent: chicken['sent'] == true,
      chickenInboxId: (chicken['inboxId'] as num?)?.toInt(),
      broadcastStatus: (j['broadcast'] is Map)
          ? (j['broadcast'] as Map)['status']?.toString()
          : null,
      myPrize: CheerPrize.fromJson(j['my_prize']),
      prizeBanner: CheerPrizeBanner.fromJson(j['prize_banner']),
    );
  }

  CheerAwardRank? get first => top.isEmpty ? null : top.first;
}

class CheerAwardRank {
  final int rank;
  final String name;
  final int count;
  final bool me;
  const CheerAwardRank(
      {required this.rank,
      required this.name,
      required this.count,
      required this.me});

  factory CheerAwardRank.fromJson(Map<String, dynamic> j) => CheerAwardRank(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '익명의 서포터',
        count: (j['count'] as num?)?.toInt() ?? 0,
        me: j['me'] == true,
      );
}

/// GET /api/cheer/status 응답
class CheerStatus {
  final int today;
  final int dailyLimit;
  /// 등급별 승급 임계값 — 콘솔 원격설정(cheer.tier_thresholds). null=구서버.
  /// UI 진입 시 CheerTierTheme.applyThresholds 로 반영한다.
  final List<int>? tierThresholds;
  final int total;
  final int streak; // 연속 응원 일수 (오늘 포함)
  /// 등급별 획득일 {'1': 'YYYY-MM-DD', ...} — 등급 상세 팝업 표시용
  final Map<String, String> tierAcquiredAt;
  final String month; // '2026-08'
  final int serverCount;
  final int serverGoal;
  final double serverPct; // 0~100
  /// 어제 목표를 채웠으면 그 수치 (못 채운 날은 null — 실패는 표시하지 않는다)
  final int? yesterdayCount;
  /// 월간 랭킹 이벤트 — 서버에서 켜졌을 때만 non-null
  final CheerEvent? event;

  /// 홈 상단 응원 스트립 노출 여부 — 콘솔 원격설정 `cheer.home_strip`.
  /// 구서버(필드 없음)는 true 로 읽는다 — 설정이 안 내려온다고 기능이 사라지면 안 된다.
  final bool homeStrip;

  /// 스트립 문구 오버라이드 — 콘솔 `cheer.home_strip_message` / `_done_message`.
  /// null 이면 앱 기본 문구(CheerStrip 상수)를 쓴다.
  final String? homeStripMessage;
  final String? homeStripDoneMessage;

  /// 왕관 이력(최신순) · 개수(금/은/동) · 아직 축하 연출을 안 본 왕관
  final List<CheerCrown> crowns;
  final Map<String, int> crownCounts;
  final CheerCrown? newCrown;

  /// 등급별 차 바디 컬러 {등급: paintId} — 저장한 등급만 들어온다.
  /// 로그인 사용자는 계정 저장분, 비회원은 기기 저장분(앱은 로컬 Hive 를 쓴다).
  /// **null = 서버가 모름**(조회 실패). {} 인 '저장 없음'과 구분해야 한다 — parseCarPaints 참고.
  final Map<int, String>? carPaints;

  const CheerStatus({
    required this.today,
    required this.dailyLimit,
    this.tierThresholds,
    required this.total,
    required this.streak,
    this.tierAcquiredAt = const {},
    required this.month,
    required this.serverCount,
    required this.serverGoal,
    required this.serverPct,
    this.yesterdayCount,
    this.event,
    this.homeStrip = true,
    this.homeStripMessage,
    this.homeStripDoneMessage,
    this.crowns = const [],
    this.crownCounts = const {},
    this.newCrown,
    this.carPaints, // 기본 null = 모름 (const {} 로 두면 '저장 없음'으로 오독된다)
  });

  factory CheerStatus.fromJson(Map<String, dynamic> j) {
    final server = (j['server'] as Map?) ?? const {};
    return CheerStatus(
      today: (j['today'] as num?)?.toInt() ?? 0,
      dailyLimit: (j['dailyLimit'] as num?)?.toInt() ?? 3,
      tierThresholds: j['tierThresholds'] is List
          ? (j['tierThresholds'] as List)
              .map((v) => (v as num).toInt())
              .toList()
          : null,
      total: (j['total'] as num?)?.toInt() ?? 0,
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      tierAcquiredAt: (j['tierAcquiredAt'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      month: server['month']?.toString() ?? '',
      serverCount: (server['count'] as num?)?.toInt() ?? 0,
      serverGoal: (server['goal'] as num?)?.toInt() ?? 1,
      serverPct: (server['pct'] as num?)?.toDouble() ?? 0,
      yesterdayCount:
          ((j['yesterdayFull'] as Map?)?['count'] as num?)?.toInt(),
      event: j['event'] is Map
          ? CheerEvent.fromJson(Map<String, dynamic>.from(j['event'] as Map))
          : null,
      crowns: ((j['crowns'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CheerCrown.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      crownCounts: (j['crownCounts'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
          const {},
      newCrown: j['newCrown'] is Map
          ? CheerCrown.fromJson(Map<String, dynamic>.from(j['newCrown'] as Map))
          : null,
      carPaints: parseCarPaints(j['carPaints']),
      // 명시적으로 false 일 때만 끈다 — 필드가 없는 구서버는 노출 유지.
      homeStrip: j['homeStrip'] != false,
      homeStripMessage: (j['homeStripMessage'] as String?)?.trim().isNotEmpty ==
              true
          ? (j['homeStripMessage'] as String).trim()
          : null,
      homeStripDoneMessage:
          (j['homeStripDoneMessage'] as String?)?.trim().isNotEmpty == true
              ? (j['homeStripDoneMessage'] as String).trim()
              : null,
    );
  }

  bool get doneToday => today >= dailyLimit;
  CheerBadge get badge => CheerBadge.of(total);
  CheerBadge? get nextBadge => CheerBadge.nextOf(total);
}

/// 개발자 응원하기 — 서버 적립 API + 보상형 광고 로드/표시.
/// 강제성 없는 순수 응원 기능이라 실패는 전부 조용히 처리(앱 사용 방해 금지).
class CheerService {
  CheerService._();
  static final CheerService instance = CheerService._();

  static const _hiveTotalKey = 'cheer_total'; // 설정 타일 뱃지 표시용 캐시
  // 홈 스트립 노출 플래그 캐시 — status 응답 전(콜드스타트·오프라인)에도 마지막으로
  // 알던 상태로 그린다. 없으면 노출(true). 이게 없으면 콘솔에서 껐는데도 앱을 켤
  // 때마다 스트립이 한 번 번쩍이고 사라진다.
  static const _hiveHomeStripKey = 'cheer_home_strip';

  /// 누적 횟수 반응형 알림 — 마이페이지 프로필 카드·설정 타일이 구독한다.
  /// 콘솔에서 리셋해도 캐시가 옛 값으로 남아 뱃지가 그대로 보이던 문제(형 제보):
  /// 서버 상태를 받아올 때마다 여기로 흘려 화면들이 즉시 따라오게 한다.
  late final ValueNotifier<int> totalNotifier = ValueNotifier(cachedTotal);

  DateTime? _lastFetch;

  /// 마지막 조회가 오래됐으면 서버와 동기화 (마이페이지 진입 시 호출, 쿨다운 2분).
  void refreshIfStale() {
    final now = DateTime.now();
    if (_lastFetch != null &&
        now.difference(_lastFetch!) < const Duration(minutes: 2)) {
      return;
    }
    _lastFetch = now;
    status(); // 성공 시 _cacheTotal → totalNotifier 갱신
  }

  final _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ))
    ..transformer = BackgroundTransformer();

  Future<Options> _authOptions() async {
    final access = await AuthService.accessToken();
    return Options(headers: {
      'x-device-id': DkswCore.deviceId,
      if (access != null) 'Authorization': 'Bearer $access',
    });
  }

  /// 마지막으로 알고 있는 누적 횟수 (네트워크 없이 설정 타일 뱃지 표시).
  int get cachedTotal {
    try {
      return (Hive.box('settings').get(_hiveTotalKey) as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _cacheTotal(int total) {
    try {
      Hive.box('settings').put(_hiveTotalKey, total);
    } catch (_) {}
    totalNotifier.value = total;
  }

  /// 마지막으로 알고 있는 홈 스트립 노출 여부 (네트워크 없이 홈이 바로 판단).
  bool get cachedHomeStrip {
    try {
      return Hive.box('settings').get(_hiveHomeStripKey, defaultValue: true) ==
          true;
    } catch (_) {
      return true;
    }
  }

  void _cacheHomeStrip(bool on) {
    try {
      Hive.box('settings').put(_hiveHomeStripKey, on);
    } catch (_) {}
    homeStripNotifier.value = on;
  }

  // 스트립 문구 캐시 — 노출 플래그와 같은 이유(status 응답 전 콜드스타트에서
  // 콘솔 문구 ↔ 기본 문구가 번쩍이며 바뀌지 않게). null = 오버라이드 없음.
  static const _hiveHomeStripMsgKey = 'cheer_home_strip_msg';
  static const _hiveHomeStripDoneMsgKey = 'cheer_home_strip_done_msg';

  String? get cachedHomeStripMessage {
    try {
      final v = Hive.box('settings').get(_hiveHomeStripMsgKey) as String?;
      return (v != null && v.trim().isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  String? get cachedHomeStripDoneMessage {
    try {
      final v = Hive.box('settings').get(_hiveHomeStripDoneMsgKey) as String?;
      return (v != null && v.trim().isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  void _cacheHomeStripMessages(CheerStatus st) {
    try {
      final box = Hive.box('settings');
      // 콘솔에서 문구를 비우면(서버 null) 캐시도 지워 기본 문구로 되돌아간다.
      if (st.homeStripMessage != null) {
        box.put(_hiveHomeStripMsgKey, st.homeStripMessage);
      } else {
        box.delete(_hiveHomeStripMsgKey);
      }
      if (st.homeStripDoneMessage != null) {
        box.put(_hiveHomeStripDoneMsgKey, st.homeStripDoneMessage);
      } else {
        box.delete(_hiveHomeStripDoneMsgKey);
      }
    } catch (_) {}
  }

  /// 홈 스트립 노출 반응형 알림 — 홈의 `CheerStrip` 이 구독한다.
  late final ValueNotifier<bool> homeStripNotifier =
      ValueNotifier(cachedHomeStrip);

  // ── 오늘 응원 횟수 캐시 ────────────────────────────────────────
  // status 응답이 오기 전에도 홈 스트립이 **정확한 상태로 한 번에** 그려지게 한다.
  // 이게 없으면 오늘 3/3 을 다 채운 사람이 홈에 올 때마다 '응원' 버튼이 먼저 떴다가
  // 응답이 도착하는 순간 '오늘 만땅!' 으로 바뀌어 깜빡인다(형 제보).
  static const _hiveDailyDayKey = 'cheer_daily_day';
  static const _hiveDailyTodayKey = 'cheer_daily_today';
  static const _hiveDailyLimitKey = 'cheer_daily_limit';

  /// 서버 집계 기준일과 맞추기 위해 KST 로 계산한다 — 기기 시간대가 뭐든 같은 날.
  static String _kstDay() {
    final d = DateTime.now().toUtc().add(const Duration(hours: 9));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  /// 마지막으로 알던 오늘 응원 횟수. **날짜가 바뀌었으면 0** — 어제 3/3 이었다고
  /// 오늘 아침에 '만땅'으로 보이면 안 된다.
  int get cachedToday {
    try {
      final box = Hive.box('settings');
      if (box.get(_hiveDailyDayKey) != _kstDay()) return 0;
      return (box.get(_hiveDailyTodayKey) as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  int get cachedDailyLimit {
    try {
      return (Hive.box('settings').get(_hiveDailyLimitKey) as num?)?.toInt() ??
          3;
    } catch (_) {
      return 3;
    }
  }

  void _cacheDaily(CheerStatus st) {
    try {
      Hive.box('settings')
        ..put(_hiveDailyDayKey, _kstDay())
        ..put(_hiveDailyTodayKey, st.today)
        ..put(_hiveDailyLimitKey, st.dailyLimit);
    } catch (_) {}
  }

  Future<CheerStatus?> status() async {
    // 미전송 적립을 먼저 흘려보낸다 — 이번 status 에 반영돼서 내려오도록.
    await flushPendingCheers();
    try {
      final res = await _dio.get('/cheer/status', options: await _authOptions());
      final st = CheerStatus.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      CheerBadge.applyThresholds(st.tierThresholds); // 원격설정 임계값 반영(+Hive)
      lastStatus = st; // 세터가 total·homeStrip·오늘횟수 캐시까지 같이 쓴다
      return st;
    } catch (_) {
      return null;
    }
  }

  /// 최근 status 스냅샷 — 프로필/개러지/설정 진입 카드가 네트워크 없이 그린다.
  /// 값이 바뀌면 구독한 화면(설정 카드의 오늘 응원 도트 등)이 바로 따라온다.
  final ValueNotifier<CheerStatus?> statusNotifier = ValueNotifier(null);
  CheerStatus? get lastStatus => statusNotifier.value;

  /// 최신 상태를 넣는 **단 하나의 입구**. 여기서 캐시까지 같이 쓴다.
  ///
  /// 예전엔 캐시 갱신을 호출부마다 따로 했더니 적립(cheer/flush) 경로가 빠져 있었다.
  /// 그래서 오늘 3번째 응원을 마쳐도 Hive 엔 2 가 남아, 다음에 홈에 들어오면
  /// '응원' 버튼이 떴다가 status 응답이 오는 순간 '오늘 만땅!' 으로 획 바뀌었다(형 제보).
  /// 세터에 모아두면 새 경로가 생겨도 자동으로 따라온다.
  set lastStatus(CheerStatus? v) {
    statusNotifier.value = v;
    if (v == null) return;
    _cacheTotal(v.total);
    _cacheHomeStrip(v.homeStrip);
    _cacheHomeStripMessages(v);
    _cacheDaily(v);
  }

  /// 로그인 여부 — 차 컬러를 서버에 저장할지(회원) 로컬에만 둘지(비회원) 가른다.
  Future<bool> get signedIn async => (await AuthService.accessToken()) != null;

  /// 개러지 차 바디 컬러 저장. paintId 'default' 면 서버에서 지운다.
  /// 실패해도 앱 사용을 막지 않는다 — 로컬 값은 이미 반영돼 있다.
  Future<bool> saveCarPaint(int tierLevel, String paintId) async {
    try {
      await _dio.post('/cheer/car-paint',
          data: {
            'device_id': DkswCore.deviceId,
            'tier': tierLevel,
            'paint': paintId,
          },
          options: await _authOptions());
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Cheer] 차 컬러 저장 실패: $e');
      return false;
    }
  }

  /// 월간 시상식 데이터 — month 미지정이면 지난달 결산.
  Future<CheerAwards?> awards({String? month}) async {
    try {
      final res = await _dio.get('/cheer/awards',
          queryParameters: {if (month != null) 'month': month},
          options: await _authOptions());
      return CheerAwards.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
    } catch (_) {
      return null;
    }
  }

  /// 축하 연출을 봤다고 서버에 알린다(다음 진입부터 안 뜨게). 실패해도 조용히.
  Future<void> markCrownSeen() async {
    try {
      await _dio.post('/cheer/crown-seen',
          data: {'device_id': DkswCore.deviceId},
          options: await _authOptions());
    } catch (_) {}
  }

  // ─── 적립 보장 큐 ──────────────────────────────────────────────────────────
  // 광고는 이미 끝까지 봤다 — 적립이 유실되면 안 된다(형 지시). 광고 1회마다 고유
  // client_key 를 만들어 큐에 넣고 전송하고, 성공해야 큐에서 뺀다. 실패분은 다음
  // preload/status 때 재전송한다. 서버가 같은 키를 dedupe 하므로 몇 번을 다시 보내도
  // 중복 적립이 없다 — "기록은 됐는데 응답만 깨진" 경우도 재전송이 성공으로 돌아온다.
  static const _pendingKey = 'cheer_pending_keys';

  List<String> _pendingKeys() {
    try {
      final raw = Hive.box('settings').get(_pendingKey);
      if (raw is List) return raw.whereType<String>().toList();
    } catch (_) {}
    return [];
  }

  void _setPendingKeys(List<String> keys) {
    try {
      // 폭주 방지 — 하루 한도가 3회라 20개면 이미 비정상. 오래된 것부터 버린다.
      Hive.box('settings').put(_pendingKey, keys.take(20).toList());
    } catch (_) {}
  }

  String _newClientKey() {
    final r = math.Random();
    final rand = List.generate(4, (_) => r.nextInt(0x10000).toRadixString(16));
    return 'c${DateTime.now().millisecondsSinceEpoch}-${rand.join()}';
  }

  bool _flushing = false;

  /// 미전송 적립 재시도 — 화면 진입·광고 preload 시 호출. 조용히, 최대 1개씩 순서대로.
  Future<void> flushPendingCheers() async {
    if (_flushing) return;
    final keys = _pendingKeys();
    if (keys.isEmpty) return;
    _flushing = true;
    try {
      for (final key in List<String>.from(keys)) {
        final st = await _postCheer(key);
        if (st == null) break; // 여전히 실패 — 네트워크 문제. 다음 기회에.
        final remain = _pendingKeys()..remove(key);
        _setPendingKeys(remain);
        lastStatus = st;
      }
    } finally {
      _flushing = false;
    }
  }

  /// 광고 시청 완료 후 적립. 성공/한도초과 모두 최신 상태를 돌려준다.
  /// 실패(null)여도 client_key 가 큐에 남아 나중에 자동 재전송된다.
  Future<CheerStatus?> cheer() async {
    final key = _newClientKey();
    _setPendingKeys(_pendingKeys()..add(key)); // 먼저 큐에 — 전송 중 크래시에도 생존
    final st = await _postCheer(key);
    if (st != null) {
      _setPendingKeys(_pendingKeys()..remove(key));
      lastStatus = st; // 설정 진입 카드의 '오늘 응원 n/3' 이 바로 따라오게
    }
    return st;
  }

  Future<CheerStatus?> _postCheer(String clientKey) async {
    try {
      final res = await _dio.post('/cheer',
          data: {'device_id': DkswCore.deviceId, 'client_key': clientKey},
          options: await _authOptions());
      final st = CheerStatus.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      CheerBadge.applyThresholds(st.tierThresholds);
      _cacheTotal(st.total);
      return st;
    } on DioException catch (e) {
      // 429 = 오늘 한도 — 서버가 현재 상태를 같이 준다. 적립 자체가 거절된 것이므로
      // 이 키는 재시도해도 영영 안 들어간다 → 큐에서 지우도록 상태를 돌려준다.
      final d = e.response?.data;
      if (d is Map && d['data'] is Map) {
        final st =
            CheerStatus.fromJson(Map<String, dynamic>.from(d['data'] as Map));
        _cacheTotal(st.total);
        return st;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── 보상형 광고 ───────────────────────────────────────────────────────────

  RewardedAd? _ad;
  bool _loading = false;

  bool get adReady => _ad != null;
  bool get adLoading => _loading;

  /// 광고 미리 로드 (화면 진입 시 + 소비 후 재호출).
  /// AdMob 이 아닌 네트워크 모드(off/adfit)면 로드하지 않는다 — 보상형은 AdMob 전용.
  /// 화면 갱신 콜백 — 한 번 등록되면 이후 preload(콜백 없이 호출되는 경로 포함)에서도
  /// 로드 완료를 화면에 알린다. 이게 없어서 광고 소비 후 재로드가 끝나도 버튼이
  /// '광고 불러오는 중…' 에 멈춰 있었다(형 제보).
  VoidCallback? _onChanged;

  /// 로드 실패 — 버튼을 '다시 시도' 로 바꿔 사용자가 직접 풀 수 있게 한다.
  bool _loadFailed = false;
  bool get adLoadFailed => _loadFailed;

  void preload({VoidCallback? onChanged}) {
    if (onChanged != null) _onChanged = onChanged;
    flushPendingCheers(); // 미전송 적립 재시도 — 광고 준비 시점마다 조용히 (fire-and-forget)
    if (AdNetworkConfig.current != AdNetwork.admob) return;
    if (_ad != null || _loading) return;
    _loading = true;
    _loadFailed = false;
    _onChanged?.call();
    RewardedAd.load(
      adUnitId: AdUnitIds.cheerRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          _loadFailed = false;
          _onChanged?.call();
        },
        onAdFailedToLoad: (e) {
          if (kDebugMode) debugPrint('[Cheer] rewarded load 실패: ${e.message}');
          _ad = null;
          _loading = false;
          _loadFailed = true;
          _onChanged?.call();
        },
      ),
    );
  }

  /// 사용자가 직접 누르는 재시도 — 로딩 상태가 끼어 멈춘 경우까지 강제로 푼다.
  void retryLoad({VoidCallback? onChanged}) {
    _loading = false;
    _loadFailed = false;
    preload(onChanged: onChanged);
  }

  /// 보상형 광고를 띄운 시점을 서버에 남긴다 — 콘솔 완료율(요청 대비 리워드) 산출용.
  /// 실패해도 광고 흐름을 막지 않는다.
  void reportAdStart() {
    _dio
        .post('/cheer/ad-start', data: {'device_id': DkswCore.deviceId})
        .catchError((_) => Response(requestOptions: RequestOptions(path: '')));
  }

  /// 광고 표시. 사용자가 끝까지 봐서 리워드를 받으면 onEarned 호출.
  /// (적립 API 호출은 화면 쪽에서 — UI 갱신 흐름을 한 곳에 모으기 위해)
  Future<void> show({
    required VoidCallback onEarned,
    VoidCallback? onDismissed,
  }) async {
    final ad = _ad;
    if (ad == null) return;
    _ad = null;
    _onChanged?.call(); // 소비됨 — 버튼 상태 즉시 갱신
    reportAdStart();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        if (kDebugMode) debugPrint('[Cheer] rewarded show 실패: ${e.message}');
        ad.dispose();
        onDismissed?.call();
      },
    );
    await ad.show(onUserEarnedReward: (_, reward) {
      if (earned) return; // 콜백 중복 방어
      earned = true;
      onEarned();
    });
  }

  void clearOnChanged() {
    _onChanged = null;
  }

  void disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loading = false;
  }

  /// iOS 는 보상형도 ATT 이후 로드가 정석이지만, 앱 부트에서 이미 ATT/UMP 를
  /// 처리하므로 여기서 별도 처리 없음. (main 부트 시퀀스 참조)
  static bool get supported => Platform.isAndroid || Platform.isIOS;
}
