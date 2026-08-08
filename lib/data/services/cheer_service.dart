import 'dart:io';

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

  static const tiers = [
    CheerBadge._(1, '쿠페 서포터', 1),
    CheerBadge._(2, '스포츠카 서포터', 10),
    CheerBadge._(3, '슈퍼카 서포터', 40),
    CheerBadge._(4, '하이퍼카 서포터', 120),
  ];

  static const none = CheerBadge._(0, '', 0);

  /// 누적 횟수 → 현재 뱃지 (0회면 none)
  static CheerBadge of(int total) {
    CheerBadge cur = none;
    for (final t in tiers) {
      if (total >= t.threshold) cur = t;
    }
    return cur;
  }

  /// 다음 등급 (만땅이면 null)
  static CheerBadge? nextOf(int total) {
    for (final t in tiers) {
      if (total < t.threshold) return t;
    }
    return null;
  }
}

/// GET /api/cheer/status 응답
class CheerStatus {
  final int today;
  final int dailyLimit;
  final int total;
  final int streak; // 연속 응원 일수 (오늘 포함)
  final String month; // '2026-08'
  final int serverCount;
  final int serverGoal;
  final double serverPct; // 0~100

  const CheerStatus({
    required this.today,
    required this.dailyLimit,
    required this.total,
    required this.streak,
    required this.month,
    required this.serverCount,
    required this.serverGoal,
    required this.serverPct,
  });

  factory CheerStatus.fromJson(Map<String, dynamic> j) {
    final server = (j['server'] as Map?) ?? const {};
    return CheerStatus(
      today: (j['today'] as num?)?.toInt() ?? 0,
      dailyLimit: (j['dailyLimit'] as num?)?.toInt() ?? 3,
      total: (j['total'] as num?)?.toInt() ?? 0,
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      month: server['month']?.toString() ?? '',
      serverCount: (server['count'] as num?)?.toInt() ?? 0,
      serverGoal: (server['goal'] as num?)?.toInt() ?? 1,
      serverPct: (server['pct'] as num?)?.toDouble() ?? 0,
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
  }

  Future<CheerStatus?> status() async {
    try {
      final res = await _dio.get('/cheer/status', options: await _authOptions());
      final st = CheerStatus.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      _cacheTotal(st.total);
      return st;
    } catch (_) {
      return null;
    }
  }

  /// 광고 시청 완료 후 적립. 성공/한도초과 모두 최신 상태를 돌려준다.
  Future<CheerStatus?> cheer() async {
    try {
      final res = await _dio.post('/cheer',
          data: {'device_id': DkswCore.deviceId},
          options: await _authOptions());
      final st = CheerStatus.fromJson(
          Map<String, dynamic>.from(res.data['data'] as Map));
      _cacheTotal(st.total);
      return st;
    } on DioException catch (e) {
      // 429 = 오늘 한도 — 서버가 현재 상태를 같이 준다.
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
  void preload({VoidCallback? onChanged}) {
    if (AdNetworkConfig.current != AdNetwork.admob) return;
    if (_ad != null || _loading) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: AdUnitIds.cheerRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          onChanged?.call();
        },
        onAdFailedToLoad: (e) {
          if (kDebugMode) debugPrint('[Cheer] rewarded load 실패: ${e.message}');
          _ad = null;
          _loading = false;
          onChanged?.call();
        },
      ),
    );
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

  void disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loading = false;
  }

  /// iOS 는 보상형도 ATT 이후 로드가 정석이지만, 앱 부트에서 이미 ATT/UMP 를
  /// 처리하므로 여기서 별도 처리 없음. (main 부트 시퀀스 참조)
  static bool get supported => Platform.isAndroid || Platform.isIOS;
}
