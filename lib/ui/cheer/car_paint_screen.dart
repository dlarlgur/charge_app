import 'package:flutter/material.dart';

import '../../core/util/app_toast.dart';
import 'car_paint.dart';
import 'cheer_tier_theme.dart';

/// 내 차 꾸미기 — handoff 2 (CheerMain.html 5a-3 패널).
/// 보유한 차의 바디 컬러를 고른다. 비회원은 기기에만, 로그인 회원은 계정에 저장돼
/// 기기를 바꿔도 따라온다(저장은 CarPaintService).
class CarPaintScreen extends StatefulWidget {
  final CheerTierTheme tier;

  /// 미드나잇 블랙 해금 판정용 누적 응원 횟수
  final int total;

  const CarPaintScreen({super.key, required this.tier, required this.total});

  @override
  State<CarPaintScreen> createState() => _CarPaintScreenState();
}

class _CarPaintScreenState extends State<CarPaintScreen> {
  late CarPaint _selected;
  late CarPaint _applied;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    CarPaintService.instance.init();
    _applied = CarPaintService.instance.of(widget.tier.level);
    _selected = _applied;
  }

  bool _locked(CarPaint p) => !p.unlockedFor(widget.total);

  /// '스포츠카 서포터' → '스포츠카' — 잠금 안내·보상 태그용 짧은 등급명
  String _tierTag(int level) =>
      CheerTierTheme.byLevel(level).name.replaceAll(' 서포터', '');

  /// 기본 컬러의 스와치는 등급 자기 차체색으로 그린다.
  List<Color> _swatchOf(CarPaint p) => p.isDefault
      ? [widget.tier.heroGlow.withValues(alpha: 0.85), widget.tier.heroGlow]
      : p.swatch;

  /// 선택 컬러의 강조색 — 카드 라벨·보더·CTA 그라디언트에 쓴다.
  /// 펄 화이트처럼 밝은 색은 라이트 모드에서 묻히므로 살짝 어둡게 눌러 쓴다.
  Color _accent(bool isDark) {
    if (_selected.isDefault) return widget.tier.heroGlow;
    final c = isDark ? _selected.swatch.first : _selected.swatch.last;
    if (!isDark && c.computeLuminance() > 0.55) {
      return Color.lerp(c, const Color(0xFF334155), 0.45)!;
    }
    return c;
  }

  /// CTA 버튼 위 글자/아이콘 색 — 밝은 컬러(펄 화이트) 위에서는 짙은 잉크로.
  Color _ctaFg() => _swatchOf(_selected).last.computeLuminance() > 0.55
      ? const Color(0xFF1E293B)
      : Colors.white;

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await CarPaintService.instance.set(widget.tier.level, _selected);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _applied = _selected;
    });
    showAppToast(
        context,
        ok
            ? '${_selected.isDefault ? '기본 컬러' : _selected.name}로 바꿨어요'
            : '컬러는 이 기기에 저장했어요. 서버 저장은 잠시 뒤 다시 시도해주세요');
  }

  Future<void> _reset() async {
    setState(() => _selected = CarPaint.original);
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(isDark);

    return Scaffold(
      backgroundColor: CheerDs.bg(isDark),
      appBar: AppBar(
        backgroundColor: CheerDs.bg(isDark),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('내 차 꾸미기',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  _hero(isDark),
                  const SizedBox(height: 12),
                  _paletteCard(isDark, accent),
                  const SizedBox(height: 12),
                  _previewCard(isDark, accent),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _swatchOf(_selected).first,
                            _swatchOf(_selected).last,
                          ],
                        ),
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _saving || _selected.id == _applied.id
                            ? null
                            : _apply,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_saving)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _ctaFg()),
                              )
                            else
                              Icon(Icons.format_paint_rounded,
                                  size: 18, color: _ctaFg()),
                            const SizedBox(width: 7),
                            Text(
                                _selected.id == _applied.id
                                    ? '적용된 컬러예요'
                                    : '이 컬러로 적용',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _ctaFg())),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: _saving || _applied.isDefault ? null : _reset,
                      child: Text('기본 컬러로 되돌리기',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CheerDs.muted(isDark))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 히어로 ───
  /// 정적 스테이지 — 상시 애니메이션은 승급 연출 전용(형 지시: 메인·꾸미기에서
  /// 차가 움직이면 안 된다). 화면폭 계산 대신 고정폭 200 스테이지를 Center 로
  /// 앉혀 광고 복귀 직후처럼 폭이 출렁여도 차가 옆으로 튀지 않는다.
  Widget _hero(bool isDark) {
    final sw = _swatchOf(_selected);
    // 큰 폰에서는 차를 비례해 키운다 (기준 390dp, 최대 1.25배)
    final k =
        (MediaQuery.sizeOf(context).width / 390).clamp(1.0, 1.25).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        children: [
          SizedBox(
            height: 104 * k,
            child: Center(
              child: Transform.scale(
                scale: k,
                child: SizedBox(
                  width: 200,
                  height: 104,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 10,
                        child: Container(
                          width: 200,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              sw.last.withValues(alpha: isDark ? 0.26 : 0.20),
                              sw.last.withValues(alpha: 0),
                            ]),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 14,
                        child: CarImage(
                            tier: widget.tier,
                            paint: _selected,
                            width: 200,
                            height: 80),
                      ),
                      Positioned(
                        left: 20,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(widget.tier.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: CheerDs.ink(isDark))),
          const SizedBox(height: 3),
          Text('컬러를 골라 내 개러지를 꾸며보세요',
              style: TextStyle(fontSize: 11, color: CheerDs.muted(isDark))),
        ],
      ),
    );
  }

  // ─── 바디 컬러 스와치 ───
  Widget _paletteCard(bool isDark, Color accent) {
    final basics = CarPaint.all.where((p) => !p.isPremium).toList();
    final premiums = CarPaint.all.where((p) => p.isPremium).toList();
    final anyLocked = premiums.any(_locked);

    return Container(
      decoration: BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('바디 컬러',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: CheerDs.ink(isDark))),
            const Spacer(),
            Text(_selected.name,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < basics.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                _swatch(basics[i], isDark),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Text('유광 프리미엄',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: CheerDs.ink(isDark))),
            const SizedBox(width: 6),
            Text('승급 보상',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: CheerDs.muted(isDark))),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < premiums.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                Column(
                  children: [
                    _swatch(premiums[i], isDark),
                    const SizedBox(height: 6),
                    Text(_tierTag(premiums[i].minLevel),
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _locked(premiums[i])
                                ? CheerDs.muted(isDark)
                                : CheerDs.ink(isDark))),
                  ],
                ),
              ],
            ],
          ),
          if (anyLocked) ...[
            const SizedBox(height: 12),
            Center(
              child: Text('응원 등급이 오를 때마다 유광 컬러가 하나씩 열려요',
                  style: TextStyle(fontSize: 10, color: CheerDs.muted(isDark))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _swatch(CarPaint p, bool isDark) {
    final locked = _locked(p);
    final on = _selected.id == p.id;
    final sw = _swatchOf(p);
    final ring = isDark ? const Color(0xFF12141A) : Colors.white;
    // 펄 화이트는 흰 체크가 안 보이므로 짙은 잉크로
    final markColor = sw.last.computeLuminance() > 0.55
        ? const Color(0xFF334155)
        : Colors.white;

    return Semantics(
      button: true,
      selected: on,
      label: locked ? '${p.name} 잠김' : p.name,
      child: GestureDetector(
        onTap: locked
            ? () =>
                showAppToast(context, '${_tierTag(p.minLevel)} 승급 시 열리는 컬러예요')
            : () => setState(() => _selected = p),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: const Alignment(-0.5, -1),
              end: const Alignment(0.5, 1),
              colors: sw,
            ),
            border: Border.all(color: ring, width: 2),
            // 시안의 outline — 선택은 컬러 2px, 아니면 옅은 1.5px
            boxShadow: [
              BoxShadow(
                color: on
                    ? (isDark ? sw.first : sw.last)
                    : (isDark
                        ? const Color(0x24FFFFFF)
                        : const Color(0xFFE8ECF0)),
                spreadRadius: on ? 2 : 1.5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 유광 컬러는 스와치에도 글로스 하이라이트를 얹어 '유광'임이 보이게
              if (p.isPremium)
                Positioned(
                  left: 7,
                  top: 8,
                  child: Transform.rotate(
                    angle: -0.6,
                    child: Container(
                      width: 15,
                      height: 7,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(colors: [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.white.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (locked)
                Icon(Icons.lock_rounded,
                    size: 14,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8))
              else if (on)
                Icon(Icons.check_rounded, size: 16, color: markColor),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 미리보기 ───
  Widget _previewCard(bool isDark, Color accent) {
    final options = CarPaint.all.where((p) => !_locked(p)).toList();
    return Container(
      decoration: BoxDecoration(
        color: CheerDs.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CheerDs.cardBorder(isDark), width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('미리보기',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: CheerDs.ink(isDark))),
          const SizedBox(height: 10),
          // 해금이 늘면 7종까지 나오므로 가로 스크롤로 — 균등분할이면 칸이 너무 좁다
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _selected = options[i]),
                child: Container(
                  width: 72,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isDark ? const Color(0x0AFFFFFF) : CheerDs.bgL,
                    border: Border.all(
                      color: _selected.id == options[i].id
                          ? accent
                          : CheerDs.cardBorder(isDark),
                      width: _selected.id == options[i].id ? 1.5 : 0.5,
                    ),
                  ),
                  child: CarImage(
                      tier: widget.tier,
                      paint: options[i],
                      fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
