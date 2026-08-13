import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'cheer_flow.dart';
import 'cheer_tier_theme.dart';
import 'garage_screen.dart';

/// 전기차 기름차 응원하기 — handoff 2 (CheerMain.html) 확정 시안.
/// 히어로(내 차 스테이지) + 컬러 존 계기판 카드 + 오늘의 연료 카드.
/// 광고를 끝까지 보면 에너지 오브가 차로 날아가 게이지를 올리는 리워드 연출이
/// 화면에서 1회 재생된다(시안 3·4번째 패널).
class CheerScreen extends StatefulWidget {
  const CheerScreen({super.key});

  @override
  State<CheerScreen> createState() => _CheerScreenState();
}

class _CheerScreenState extends State<CheerScreen>
    with TickerProviderStateMixin {
  CheerStatus? _status;
  bool _loading = true;
  bool _failed = false;
  bool _showing = false;

  /// 리워드 연출 1회 재생 — 시안 타임라인 총 4.7초 (design-spec 표 그대로).
  late final AnimationController _reward = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _rewardTotal));

  /// 진입·비연출 갱신용 바늘 스윕.
  late final AnimationController _needleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  double _fillFrom = 0;
  double _fillTo = 0;

  // 연출 중 게이지가 출발할 값 / 도착할 값
  double _rewardFrom = 0;
  double _rewardTo = 0;
  int _rewardFromCount = 0;

  bool get _rewardActive => _reward.isAnimating;

  @override
  void initState() {
    super.initState();
    CarPaintService.instance.init();
    _load();
    CheerService.instance.preload(onChanged: _refresh);
  }

  @override
  void dispose() {
    _reward.dispose();
    _needleCtrl.dispose();
    CheerService.instance.disposeAd();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final st = await CheerService.instance.status();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = st == null;
      _status = st;
    });
    if (st == null) return;
    // 콘솔 원격설정 승급 임계값 반영 — 등급 판정·해금 표시가 서버 값을 따르게.
    CheerTierTheme.applyThresholds(st.tierThresholds);
    _animateTo(st.serverPct / 100);
    // 로그인 회원이면 계정에 저장된 차 컬러를 따라간다(기기 바뀌어도 유지).
    CarPaintService.instance.applyServer(st.carPaints,
        signedIn: await CheerService.instance.signedIn);
  }

  void _animateTo(double target) {
    _fillFrom = _fillTo;
    _fillTo = target.clamp(0.0, 1.0);
    _needleCtrl.forward(from: 0);
  }

  /// 광고를 끝까지 본 뒤 — 값은 즉시 반영하되 게이지 숫자·바늘은 연출에 맡긴다.
  /// 적립 직전 수치를 잡아둬야 숫자 스왑(이전→이후)이 실제 값으로 돌아간다.
  void _applyStatus(CheerStatus st) {
    if (!mounted) return;
    CheerTierTheme.applyThresholds(st.tierThresholds);
    _rewardFromCount = _status?.serverCount ?? st.serverCount;
    setState(() => _status = st);
  }

  /// 리워드 연출 1회 재생. reduce-motion 이면 건너뛰고 즉시 게이지에 반영한다.
  Future<void> _playReward(CheerStatus st) async {
    if (!mounted) return;
    final target = (st.serverPct / 100).clamp(0.0, 1.0);
    if (MediaQuery.of(context).disableAnimations) {
      setState(() {
        _fillFrom = target;
        _fillTo = target;
      });
      _needleCtrl.value = 1;
      return;
    }
    _rewardFrom = _fillTo;
    _rewardTo = target;
    await _reward.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _fillFrom = target;
      _fillTo = target;
    });
    _needleCtrl.value = 1;
  }

  Future<void> _watchAd() async {
    if (_showing) return;
    setState(() => _showing = true);
    final started = await runCheerAdFlow(
      context,
      inlineReward: true, // 감사 시트 대신 화면 안에서 리워드 연출
      onStatus: _applyStatus,
      onCelebrationClosed: _playReward,
    );
    if (!started) CheerService.instance.preload(onChanged: _refresh);
    if (mounted) setState(() => _showing = false);
  }

  void _openGarage() {
    final st = _status;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GarageScreen(initialStatus: st)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: CheerDs.bg(isDark),
      appBar: AppBar(
        backgroundColor: CheerDs.bg(isDark),
        // 시안 헤더는 iOS 스타일 화살표(arrow_back_ios_new)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('전기차 기름차 응원하기',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _retryView(isDark)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    if (_status!.yesterdayCount != null) ...[
                      _yesterdayBanner(_status!, isDark),
                      const SizedBox(height: 12),
                    ],
                    _hero(isDark),
                    const SizedBox(height: 12),
                    _gaugeCard(isDark),
                    const SizedBox(height: 12),
                    if (_status!.event != null) ...[
                      _eventCard(_status!.event!, isDark),
                      const SizedBox(height: 12),
                    ],
                    _fuelCard(isDark),
                    const SizedBox(height: 18),
                    Center(
                      child: Text('광고 수익은 전액 서버 운영비에 보태져요',
                          style: TextStyle(
                              fontSize: 10, color: CheerDs.muted(isDark))),
                    ),
                  ],
                ),
    );
  }

  Widget _retryView(bool isDark) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('응원 정보를 불러오지 못했어요',
              style: TextStyle(color: CheerDs.muted(isDark))),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('다시 시도'),
          ),
        ]),
      );

  // 풀업 DS — 카드 radius 14, border 0.5px, 그림자 없음
  BoxDecoration _card(bool isDark) => BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      );

  // 어제 목표 달성 축하 — 못 채운 날은 아예 표시하지 않는다(실패 프레임 금지, 형 확정).
  Widget _yesterdayBanner(CheerStatus st, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CheerDs.ev.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: CheerDs.ev.withValues(alpha: isDark ? 0.30 : 0.20),
            width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_rounded, size: 18, color: CheerDs.ev),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '어제 목표 달성! 모두의 응원 ${st.yesterdayCount}개, 고마워요',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: isDark ? CheerDs.success : const Color(0xFF059669),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 1. 히어로 — 내 차 스테이지 ───
  Widget _hero(bool isDark) {
    final st = _status!;
    final tier = CheerTierTheme.of(st.total) ?? CheerTierTheme.byLevel(1);
    final owned = CheerTierTheme.of(st.total) != null;
    final next = CheerTierTheme.nextOf(st.total);
    final accent = isDark ? const Color(0xFFFDBA74) : const Color(0xFFEA580C);

    // 히어로 뒤 은은한 블루 워시 — 정적 배경으로만 채운다(움직임은 승급·리워드 전용).
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0x143B82F6), Color(0x003B82F6)]
              : const [Color(0xFFEFF6FF), Color(0x00EFF6FF)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openGarage,
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Column(
              children: [
                _HeroStage(
                  tier: tier,
                  owned: owned,
                  isDark: isDark,
                  reward: _reward,
                  // 시안은 +100 고정이지만 실제 게이지 증가분을 그대로 띄운다
                  plusLabel:
                      '+${math.max(1, st.serverCount - _rewardFromCount)}',
                ),
                const SizedBox(height: 12),
                Text(owned ? tier.name : '첫 차를 기다리는 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: CheerDs.ink(isDark))),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: next == null
                                  ? '누적 ${st.total}회 · 최고 등급'
                                  : '누적 ${st.total}회 · ${next.name.replaceAll(' 서포터', '')}까지 ',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: CheerDs.secondary(isDark))),
                          if (next != null)
                            TextSpan(
                                text: '${next.threshold - st.total}회',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: accent)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 시안에는 없지만 개러지 진입점이 메인에서 사라지면 안 된다.
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: CheerDs.muted(isDark)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 2. 응원 게이지 카드 (컬러 존 세그먼트 계기판) ───
  Widget _gaugeCard(bool isDark) {
    final st = _status!;
    final k = _uiScale(context); // 큰 폰에서 계기판도 비례해 커진다
    return Container(
      decoration: _card(isDark),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104 * k,
            height: 62 * k,
            child: AnimatedBuilder(
              animation: Listenable.merge([_needleCtrl, _reward]),
              builder: (_, __) => CustomPaint(
                painter: _ZoneGaugePainter(fill: _displayFill, isDark: isDark),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 22, child: _gaugeCount(st, isDark)),
                const SizedBox(height: 3),
                Text('오늘의 응원 게이지',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: CheerDs.ink(isDark))),
                const SizedBox(height: 3),
                AnimatedBuilder(
                  animation: _reward,
                  builder: (_, __) {
                    final hot = _rewardActive && _elapsed >= 2500;
                    return Text(
                      hot ? '에너지가 도착했어요! 게이지가 올라가요' : _gaugeCopy(st),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        fontWeight: hot ? FontWeight.w600 : FontWeight.w400,
                        color: hot
                            ? CheerDs.rewardAccent(isDark)
                            : CheerDs.muted(isDark),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 숫자 스왑 — 연출 2.8s 에 이전 값이 사라지고 새 값이 아래에서 올라온다.
  Widget _gaugeCount(CheerStatus st, bool isDark) {
    return AnimatedBuilder(
      animation: _reward,
      builder: (_, __) {
        if (!_rewardActive) {
          return _countRow(st.serverCount, st.serverGoal, isDark,
              highlight: false);
        }
        final t = Curves.ease.transform(_seg(2800, 600));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: 1 - t,
              child: _countRow(_rewardFromCount, st.serverGoal, isDark,
                  highlight: false),
            ),
            Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - t)),
                child: _countRow(st.serverCount, st.serverGoal, isDark,
                    highlight: true),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _countRow(int count, int goal, bool isDark,
      {required bool highlight}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count',
            style: TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w800,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
                color: highlight
                    ? CheerDs.rewardAccent(isDark)
                    : CheerDs.ink(isDark))),
        const SizedBox(width: 3),
        Text('/ $goal',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: CheerDs.slash(isDark))),
      ],
    );
  }

  double get _elapsed => _reward.value * _rewardTotal;

  /// 연출 타임라인의 한 구간을 0~1 로 — [startMs] 에 시작해 [durMs] 동안.
  double _seg(double startMs, double durMs) =>
      ((_elapsed - startMs) / durMs).clamp(0.0, 1.0);

  /// 표시할 게이지 채움 — 연출 중이면 바늘이 목표를 지나쳤다가 좌우로
  /// 흔들리며 자리 잡는다(감쇠 진동 — 형 지시 "와리가리").
  /// 연출 중 바늘이 넘을 수 있는 상한 — 페인터가 바늘만 F 를 살짝(9°) 지나치게 그린다.
  /// 목표가 100% 여도 오버슈트가 실제로 보이게 하기 위한 여유폭.
  static const double _kGaugeCeil = 1.05;

  double get _displayFill {
    if (_rewardActive) {
      final t = _needleWiggle(_seg(2600, 1700));
      // 오버슈트가 상한(1.05)을 넘으면 넘는 만큼만 [목표, 1.05] 여유폭으로 압축.
      // 목표가 정확히 100% 라도 headroom 이 0.05 남아 있어 진동이 안 죽는다 —
      // 예전엔 상한이 1.0 이라 일일 목표를 채우는 순간(가장 축하할 때) 연출 절반이 눌렸다.
      final v = _rewardFrom + (_rewardTo - _rewardFrom) * t;
      if (v <= _kGaugeCeil) return v.clamp(0.0, _kGaugeCeil);
      final peak = _rewardFrom + (_rewardTo - _rewardFrom) * _kWigglePeak;
      if (peak <= _kGaugeCeil) return v.clamp(0.0, _kGaugeCeil);
      final headroom = _kGaugeCeil - _rewardTo;
      final excess = (v - _rewardTo) / (peak - _rewardTo); // 0~1
      return (_rewardTo + headroom * excess).clamp(0.0, _kGaugeCeil);
    }
    final t = Curves.easeOut.transform(_needleCtrl.value);
    return (_fillFrom + (_fillTo - _fillFrom) * t).clamp(0.0, 1.0);
  }

  /// _needleWiggle 의 최대값(t≈0.25) — 오버슈트 압축 계산에 쓴다.
  static const double _kWigglePeak = 1.323;

  /// 감쇠 진동 — 목표를 크게 넘었다가 두어 번 되돌아오며 정착 (0→1, 최대 ~1.32).
  static double _needleWiggle(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return 1 - math.exp(-4.2 * t) * math.cos(t * math.pi * 3.5);
  }

  /// 게이지 아래 한 줄 — 구간마다 말이 달라진다(형 지시).
  /// 0%에 "0% 채워졌어요"는 초라해서, 시작 전엔 아예 다른 문장으로 연다.
  String _gaugeCopy(CheerStatus st) {
    final pct = st.serverPct;
    if (st.serverCount == 0) return '첫 응원을 기다리고 있어요';
    if (pct >= 100) return '오늘 목표 달성! 고마워요';
    if (pct >= 80) return '거의 다 왔어요 · ${pct.round()}%';
    if (pct >= 50) return '절반을 넘었어요 · ${pct.round()}%';
    if (pct >= 20) return '차오르는 중 · ${pct.round()}%';
    return '이제 시동을 걸었어요 · ${pct.round()}%';
  }

  /// 월간 랭킹 이벤트 카드 — 서버 원격설정으로 켤 때만 나타난다(앱 배포 불필요).
  /// 사행성으로 읽히지 않게 '감사 이벤트' 톤 유지, 순위는 참고 정보로만.
  Widget _eventCard(CheerEvent ev, bool isDark) {
    final gold = isDark ? const Color(0xFFFACC15) : const Color(0xFFA16207);
    return Container(
      decoration: BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: gold.withValues(alpha: isDark ? 0.35 : 0.28), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.emoji_events_rounded, size: 16, color: gold),
            const SizedBox(width: 7),
            Expanded(
              child: Text(ev.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: CheerDs.ink(isDark))),
            ),
            if (ev.reward.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(ev.reward,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: gold)),
              ),
          ]),
          if (ev.desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(ev.desc,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: CheerDs.secondary(isDark))),
          ],
          const SizedBox(height: 11),
          for (final r in ev.top)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(
                  width: 22,
                  child: Text('${r.rank}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: r.rank == 1 ? gold : CheerDs.muted(isDark))),
                ),
                Expanded(
                  child: Text(r.me ? '${r.name} (나)' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: r.me ? FontWeight.w800 : FontWeight.w600,
                          color: r.me ? CheerDs.gas : CheerDs.ink(isDark))),
                ),
                // 남의 응원 횟수는 서버가 아예 안 내려준다(옆 세션 작업) —
                // 격차는 CheerEvent.chase* 로만 표현한다.
              ]),
            ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: CheerDs.iconBg(isDark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text('내 기록',
                  style: TextStyle(
                      fontSize: 11.5, color: CheerDs.secondary(isDark))),
              const Spacer(),
              Flexible(
                child: Text(
                    ev.myCount == 0
                        ? '아직 이번 달 응원이 없어요'
                        : '이번 달 ${ev.myCount}회'
                            '${ev.myRank != null ? ' · ${ev.myRank}위' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: CheerDs.ink(isDark))),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ─── 3. 오늘의 연료 카드 ───
  Widget _fuelCard(bool isDark) {
    final st = _status!;
    final svc = CheerService.instance;
    final remaining = (st.dailyLimit - st.today).clamp(0, st.dailyLimit);
    final done = st.doneToday;
    final ctaEnabled = !done && !_showing && svc.adReady;

    return Container(
      decoration: _card(isDark),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('오늘의 연료',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: CheerDs.ink(isDark))),
            const Spacer(),
            // 연료 도트 — 채운 칸은 블루 + 글로우, 빈 칸은 1.5px 링
            for (var i = 0; i < st.dailyLimit; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              _FuelDot(
                filled: i < st.today,
                // 방금 채워진 칸은 연출 2.9초에 톡 점등
                justLit: i == st.today - 1,
                isDark: isDark,
                reward: _reward,
                seg: _seg,
                rewardActive: () => _rewardActive,
              ),
            ],
            const SizedBox(width: 3),
            Text('${st.today}/${st.dailyLimit}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF3B82F6))),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: ctaEnabled || _showing
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: CheerDs.ctaBlue)
                        : null,
                    color:
                        ctaEnabled || _showing ? null : CheerDs.iconBg(isDark),
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: ctaEnabled ? _watchAd : null,
                    child: done
                        ? Text('오늘 응원 만땅!',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: CheerDs.muted(isDark)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_showing ||
                                  (!svc.adReady &&
                                      svc.adLoading &&
                                      !svc.adLoadFailed)) ...[
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _showing
                                          ? Colors.white
                                          : CheerDs.muted(isDark)),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                    _showing
                                        ? '광고 재생 중…'
                                        : svc.adReady
                                            ? '광고 보고 응원하기'
                                            : svc.adLoadFailed
                                                ? '광고를 못 불러왔어요'
                                                : '광고 불러오는 중…',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ctaEnabled || _showing
                                            ? Colors.white
                                            : CheerDs.muted(isDark))),
                              ),
                              if (ctaEnabled) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('$remaining번 남음',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white)),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
            // 로드가 오래 걸리거나 실패했을 때 직접 푸는 갱신 버튼 (형 요청).
            if (!done && !_showing && !svc.adReady) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: Material(
                  color: CheerDs.iconBg(isDark),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      CheerService.instance.retryLoad(onChanged: _refresh);
                      if (mounted) setState(() {});
                    },
                    child: Icon(Icons.refresh_rounded,
                        size: 21,
                        color: svc.adLoadFailed
                            ? CheerDs.gas
                            : CheerDs.muted(isDark)),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 11),
          Center(
            // 칸 수는 원격설정(cheer.daily_limit)로 바뀐다 — '3칸' 하드코딩이면 한도를
            // 조정한 순간 도트 개수와 문구가 어긋난다.
            child: Text(
                done
                    ? '내일 또 응원할 수 있어요'
                    : '${st.dailyLimit}칸을 다 채우면 "오늘 응원 만땅!"',
                style: TextStyle(fontSize: 10.5, color: CheerDs.muted(isDark))),
          ),
        ],
      ),
    );
  }
}

const int _rewardTotal = 4700;

/// 화면 폭 기준 보정 배율 — 기준 390dp. 큰 폰에서 히어로 차·게이지 계기판이
/// 상대적으로 작아 보이지 않게 최대 1.25배까지 키운다(형 요청 반응형).
double _uiScale(BuildContext context) =>
    (MediaQuery.sizeOf(context).width / 390).clamp(1.0, 1.25).toDouble();

/// 히어로 스테이지 — 정적인 글로우 + 차. 움직임은 리워드 연출(오브 비행·차 히트·
/// 링 파동·+100) 1회 재생 때만 나온다. 상시 pulse·트윙클은 승급 연출과 겹쳐 보여
/// 뺐다(형 지시: 메인에서 차 스테이지가 움직이면 안 된다).
class _HeroStage extends StatelessWidget {
  final CheerTierTheme tier;
  final bool owned;
  final bool isDark;
  final AnimationController reward;
  final String plusLabel;

  const _HeroStage({
    required this.tier,
    required this.owned,
    required this.isDark,
    required this.reward,
    required this.plusLabel,
  });

  /// 고정 스테이지 폭 — 차(200px)와 같다. 모든 좌표는 이 폭 기준.
  static const double _stageW = 200;

  // 오브 3개 — (시작 오프셋, 3차 베지어 제어점·끝점, 크기, 색) 시안 offset-path 그대로
  static const _orbs = [
    (
      Offset(-110, 100),
      [Offset(40, -70), Offset(90, -60), Offset(118, -38)],
      14.0,
      Color(0xFFBFDBFE),
      Color(0xFF3B82F6),
    ),
    (
      Offset(-114, 108),
      [Offset(30, -90), Offset(100, -70), Offset(124, -44)],
      10.0,
      Color(0xFFA7F3D0),
      Color(0xFF10B981),
    ),
    (
      Offset(-106, 104),
      [Offset(50, -50), Offset(80, -80), Offset(114, -34)],
      8.0,
      Color(0xFFFDE68A),
      Color(0xFFF59E0B),
    ),
  ];

  static Offset _cubic(Offset p0, List<Offset> c, double t) {
    final p1 = p0 + c[0], p2 = p0 + c[1], p3 = p0 + c[2];
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  double _seg(double startMs, double durMs) =>
      ((reward.value * _rewardTotal - startMs) / durMs).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    // 화면폭 기준 배치(maxWidth/2)는 광고 복귀 직후처럼 제약이 출렁이는 순간
    // 차가 옆으로 튀는 사고가 있었다(형 제보 스크린샷). 고정폭 스테이지를
    // Center 로 앉혀 어떤 폭에서도 배치가 흔들리지 않게 하고,
    // 큰 폰에서는 스테이지째 확대한다.
    const cx = _stageW / 2;
    final k = _uiScale(context);
    return SizedBox(
      height: 104 * k,
      child: Center(
        child: Transform.scale(
          scale: k,
          child: SizedBox(
            width: _stageW,
            height: 104,
            child: AnimatedBuilder(
              animation: reward,
              builder: (_, __) {
                final active = reward.isAnimating;
                // 차 히트 — 2.5s 부터 0.9s, 0.42 지점이 정점 (brightness 1.55 / scale 1.05)
                final hp = _seg(2500, 900);
                final hit = !active
                    ? 0.0
                    : (hp < 0.42 ? hp / 0.42 : (1 - hp) / 0.58).clamp(0.0, 1.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 오렌지(등급색) 글로우 — 정적
                    Positioned(
                      left: cx - 100,
                      top: 10,
                      child: Container(
                        width: 200,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            tier.heroGlow
                                .withValues(alpha: isDark ? 0.26 : 0.20),
                            tier.heroGlow.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                    // 링 파동 (2.6s+1.7s)
                    if (active)
                      Positioned(
                        left: cx - 60,
                        top: -16,
                        child: IgnorePointer(child: _ring()),
                      ),
                    // 차 + 바닥 그림자
                    Positioned(
                      left: cx - 100,
                      top: 14,
                      child: SizedBox(
                        width: 200,
                        height: 80,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (hit > 0)
                              Opacity(
                                opacity: hit,
                                child: Container(
                                  width: 190,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [
                                      CheerDs.gas.withValues(alpha: 0.55),
                                      CheerDs.gas.withValues(alpha: 0),
                                    ]),
                                  ),
                                ),
                              ),
                            Transform.scale(
                              scale: 1 + 0.05 * hit,
                              child: _carArt(hit),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: cx - 80,
                      top: 87,
                      child: Container(
                        width: 160,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: RadialGradient(colors: [
                            isDark
                                ? const Color(0x99000000)
                                : const Color(0x260F172A),
                            const Color(0x00000000),
                          ]),
                        ),
                      ),
                    ),
                    // 에너지 오브 3개 (0s 시작, 1.7s, stagger 0.5s)
                    if (active)
                      for (var i = 0; i < _orbs.length; i++) _orb(cx, i),
                    // +100 플로팅 (2.9s+1.8s)
                    if (active) _plus100(cx),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 미보유(첫 응원 전)면 실루엣, 보유면 내가 고른 바디 컬러. 히트 순간엔 밝기 1→1.55.
  Widget _carArt(double hit) {
    final car = owned
        ? CarImage(tier: tier, width: 200, height: 80)
        : tier.silhouette(CheerDs.silhouette(isDark), width: 200, height: 80);
    if (hit <= 0) return car;
    final b = 1 + 0.55 * hit;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        b, 0, 0, 0, 0, //
        0, b, 0, 0, 0, //
        0, 0, b, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: car,
    );
  }

  Widget _ring() {
    final t = Curves.easeOut.transform(_seg(2600, 1700));
    final op = t < 0.3 ? t / 0.3 * 0.9 : 0.9 * (1 - (t - 0.3) / 0.7);
    return Opacity(
      opacity: op.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.3 + 1.2 * t,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: CheerDs.gas.withValues(alpha: 0.55), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _orb(double cx, int i) {
    final o = _orbs[i];
    final t = Curves.easeIn.transform(_seg(i * 500, 1700));
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final p = _cubic(o.$1, o.$2, t);
    final size = o.$3;
    final op = t < 0.12 ? t / 0.12 : (t > 0.9 ? (1 - t) / 0.1 : 1.0);
    return Positioned(
      left: cx + p.dx - size / 2,
      top: p.dy - size / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [o.$4, o.$5],
              ),
              boxShadow: [
                BoxShadow(
                    color: o.$5.withValues(alpha: 0.65),
                    blurRadius: size * 0.9,
                    spreadRadius: size * 0.2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _plus100(double cx) {
    final t = Curves.easeOut.transform(_seg(2900, 1800));
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    // 6px 아래에서 솟아 -30px 까지 올라가며 사라진다
    final dy = t < 0.28 ? 6 - 16 * (t / 0.28) : -10 - 20 * ((t - 0.28) / 0.72);
    final op = t < 0.28 ? t / 0.28 : (t > 0.5 ? 1 - (t - 0.5) / 0.5 : 1.0);
    final sc =
        t < 0.28 ? 0.7 + 0.3 * (t / 0.28) : 1 - 0.15 * ((t - 0.28) / 0.72);
    return Positioned(
      left: cx + 2,
      top: 26 + dy,
      child: IgnorePointer(
        child: Opacity(
          opacity: op.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: sc,
            child: Text(plusLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: CheerDs.rewardAccent(isDark))),
          ),
        ),
      ),
    );
  }
}

/// 연료 도트 1칸 — 채워지면 블루 + 글로우. 방금 채워진 칸은 연출 2.9초에 점등.
class _FuelDot extends StatelessWidget {
  final bool filled;
  final bool justLit;
  final bool isDark;
  final AnimationController reward;
  final double Function(double, double) seg;
  final bool Function() rewardActive;

  const _FuelDot({
    required this.filled,
    required this.justLit,
    required this.isDark,
    required this.reward,
    required this.seg,
    required this.rewardActive,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reward,
      builder: (_, __) {
        final blue = isDark ? const Color(0xFF60A5FA) : const Color(0xFF3B82F6);
        // 연출 중이면 2.9초 전까지는 아직 안 켜진 칸으로 그린다
        final lit =
            filled && (!justLit || !rewardActive() || seg(2900, 300) > 0);
        final pop = justLit && rewardActive() ? seg(2900, 300) : 1.0;
        return Transform.scale(
          scale: lit ? 1 + 0.35 * math.sin(pop * math.pi) : 1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? blue : null,
              border: lit
                  ? null
                  : Border.all(
                      color: isDark
                          ? const Color(0x33FFFFFF)
                          : const Color(0xFFCBD5E1),
                      width: 1.5),
              boxShadow: lit
                  ? [
                      BoxShadow(
                          color: CheerDs.gas.withValues(alpha: 0.5),
                          blurRadius: 6),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// 컬러 존 세그먼트 계기판 — 시안 좌표계 104×62 (원 96×96, 중심 (52,52)).
/// 존 5개 #EF4444→#10B981, 갭 3°, 미충전 opacity 라이트 0.30 / 다크 0.50.
class _ZoneGaugePainter extends CustomPainter {
  final double fill; // 0~1.05 — 1 초과분은 바늘만 F 를 지나친다 (아크는 1.0 캡)
  final bool isDark;
  const _ZoneGaugePainter({required this.fill, required this.isDark});

  // (시작°, 길이°) — E(0°, 왼쪽)부터 시계방향으로 F(180°)까지
  static const _zones = [
    (0.0, 34.0),
    (37.0, 33.0),
    (73.0, 33.0),
    (109.0, 33.0),
    (145.0, 35.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / 104, size.height / 62);
    final ox = (size.width - 104 * k) / 2;
    final oy = (size.height - 62 * k) / 2;
    Offset pt(double x, double y) => Offset(ox + x * k, oy + y * k);
    final center = pt(52, 52);

    // 링: 바깥 반지름 48, 안쪽 마스크 58% → 두께 20.2, 중심선 반지름 37.9
    const rMid = 37.9;
    const stroke = 20.2;
    final rect = Rect.fromCircle(center: center, radius: rMid * k);
    double rad(double deg) => math.pi + deg * math.pi / 180;

    // 1) 빈 트랙
    canvas.drawArc(
      rect,
      rad(0),
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * k
        ..color = CheerDs.gaugeTrack(isDark),
    );

    // 2) 미충전 존 (연하게)
    // 아크(색 채움)는 트랙 밖을 못 그리니 1.0 캡, 바늘은 오버슈트 연출로 1.05 까지.
    final fillDeg = fill.clamp(0.0, 1.0) * 180;
    final needleDeg = fill.clamp(0.0, 1.05) * 180;
    for (var i = 0; i < _zones.length; i++) {
      final z = _zones[i];
      canvas.drawArc(
        rect,
        rad(z.$1),
        z.$2 * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * k
          ..color =
              CheerDs.gaugeZones[i].withValues(alpha: isDark ? 0.50 : 0.30),
      );
    }

    // 3) 채워진 만큼 100%
    for (var i = 0; i < _zones.length; i++) {
      final z = _zones[i];
      final end = math.min(z.$1 + z.$2, fillDeg);
      if (end <= z.$1) break;
      canvas.drawArc(
        rect,
        rad(z.$1),
        (end - z.$1) * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * k
          ..color = CheerDs.gaugeZones[i],
      );
    }

    // E / F — 9px 800
    void label(String t, {required bool left}) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                fontSize: 9 * k,
                fontWeight: FontWeight.w800,
                color: CheerDs.efLabel(isDark))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pt(left ? 0 : 104 - tp.width / k, 50));
    }

    label('E', left: true);
    label('F', left: false);

    // 바늘 — 길이 36, 두께 5, 레드 그라디언트 + 글로우
    final a = rad(needleDeg);
    final dir = Offset(math.cos(a), math.sin(a));
    final tip = center + dir * (36 * k);
    final needle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * k
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        center,
        tip,
        const [CheerDs.needleFrom, CheerDs.needleTo],
      );
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * k
        ..strokeCap = StrokeCap.round
        ..color = CheerDs.needleFrom.withValues(alpha: isDark ? 0.6 : 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * k),
    );
    canvas.drawLine(center, tip, needle);

    // 허브 — 13px 원, 카드색 + 레드 보더 3.5 (box-sizing: border-box)
    canvas.drawCircle(
        center, 6.5 * k, Paint()..color = CheerDs.gaugeGap(isDark));
    canvas.drawCircle(
      center,
      (6.5 - 1.75) * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * k
        ..color = CheerDs.needleFrom,
    );
  }

  @override
  bool shouldRepaint(_ZoneGaugePainter old) =>
      old.fill != fill || old.isDark != isDark;
}
