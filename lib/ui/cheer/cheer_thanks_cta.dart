import 'package:flutter/material.dart';

import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'cheer_screen.dart';
import 'cheer_tier_theme.dart';

/// 콘텐츠 하단 응원 유도 카드 — "이 리포트가 도움이 되셨나요?".
///
/// 설정 탭의 CheerEntryCard 가 '기능 진입점'이라면 이건 '읽고 만족한 직후'에만
/// 붙이는 권유다. 응원하기는 설정 탭 안에 있어서 존재 자체를 모르는 사용자가
/// 대부분인데, 리포트는 이미 푸시로 도달하는 화면이라 노출 채널이 공짜다.
///
/// 톤: 조르지 않는다. 한 줄 권유 + 내 차 한 줄 + 버튼으로 끝낸다.
/// 오늘 한도를 채웠으면 버튼을 감사 인사로 바꾼다 — 눌러도 응원 화면으로는 간다
/// (차고·컬러를 보러 갈 수 있어야 하므로 막지 않는다).
class CheerThanksCta extends StatefulWidget {
  const CheerThanksCta({
    super.key,
    this.message = '이 리포트가 도움이 되셨나요?',
    this.margin = const EdgeInsets.only(top: 4),
  });

  /// 화면마다 다른 첫 줄 — '이 브리핑이…' 처럼 갈아끼운다.
  final String message;
  final EdgeInsets margin;

  @override
  State<CheerThanksCta> createState() => _CheerThanksCtaState();
}

class _CheerThanksCtaState extends State<CheerThanksCta> {
  @override
  void initState() {
    super.initState();
    // 리포트로 바로 진입(푸시 딥링크)하면 응원 상태가 아직 없다 — 여기서 채운다.
    CarPaintService.instance.init();
    CheerService.instance.preload();
  }

  void _open() {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const CheerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<CheerStatus?>(
      valueListenable: CheerService.instance.statusNotifier,
      builder: (_, st, __) {
        final total = st?.total ?? CheerService.instance.cachedTotal;
        final tier = CheerTierTheme.of(total);
        final today = st?.today ?? 0;
        final limit = st?.dailyLimit ?? 3;
        final done = today >= limit;

        return Padding(
          padding: widget.margin,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _open,
              child: Ink(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? const [Color(0x243B82F6), Color(0x0B10B981)]
                        : const [Color(0xFFF2F8FF), Color(0xFFEFFBF6)],
                  ),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x4460A5FA)
                        : const Color(0xFFD9E8F7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.message,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isDark
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('광고 1번이면 응원 1개. 리포트를 계속 만드는 데 큰 힘이 됩니다.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF5B7A9C))),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        SizedBox(
                          width: 52,
                          height: 21,
                          child: tier == null
                              ? CheerTierTheme.byLevel(1).silhouette(isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFFBFD4EA))
                              : CarImage(tier: tier),
                        ),
                        const SizedBox(width: 9),
                        // Expanded 여야 버튼이 오른쪽 끝에 고정된다 — Flexible 이면
                        // 짧은 텍스트에 버튼이 붙어 320dp 에서 어색해진다.
                        Expanded(
                          child: Text(
                              tier == null
                                  ? '첫 응원을 기다리고 있어요'
                                  : '${tier.name} · 누적 $total회',
                              // 2줄 — 한 행에 [차][등급·누적][버튼] 셋이라, 폰트배율이 커지면
                              // 버튼이 넓어지면서 가운데가 '누적 2…' 로 잘렸다(형 제보).
                              // 평소엔 짧아 1줄 그대로고 배율이 클 때만 접힌다.
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFF93C5FD)
                                      : const Color(0xFF2563EB))),
                        ),
                        const SizedBox(width: 8),
                        _button(done, isDark),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _button(bool done, bool isDark) {
    if (done) {
      // 오늘 다 한 사람에게 '응원하기'를 또 들이밀면 눌렀을 때 막힌다 — 인사로 바꾼다.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: isDark ? const Color(0x5A60A5FA) : const Color(0xFFCFE4F7)),
        ),
        child: Text('오늘 응원 완료',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFF2563EB))),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: CheerDs.ctaBlue,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: isDark ? 0.34 : 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Text('응원하기',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: Colors.white)),
    );
  }
}
