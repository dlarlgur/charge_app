import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/cheer_service.dart';
import '../cheer/cheer_screen.dart';

/// 홈 요약 카드 바로 아래 응원 스트립 (핸드오프 3-3).
///
/// 스크롤과 함께 올라간다(sticky 아님). 골드는 두 탭 모두 동일 — 모드색(파랑/초록)과
/// 겹치지 않아야 눈에 띈다.
///
/// **문구 주의**: 이 앱의 '응원'은 후원 결제가 아니라 **광고 한 편 시청**이다
/// (`CheerService` · 하루 `dailyLimit` 회). 그래서 핸드오프 원문의
/// `광고 없이 만드는 앱, 28명이 응원 중이에요` 는 쓰지 않는다 — 바로 위에 광고 배너가
/// 떠 있고 응원 동작 자체가 광고 시청이라 두 번 어긋난다. 대신 무엇이 어떻게
/// 도움이 되는지 구체적으로 적는다. 문구는 아래 두 상수만 고치면 된다.
class CheerStrip extends StatefulWidget {
  const CheerStrip({super.key});

  /// 아직 오늘 응원 여력이 남은 상태.
  /// **한 줄에 들어가야 한다** — 320dp x1.2 까지 검증(home_top_renewal_layout_test).
  /// 두 줄로 넘어가면 어색하게 끊긴다(형 제보). 콘솔 원격설정
  /// `cheer.home_strip_message` 가 있으면 그 문구가 이 기본값을 덮는다.
  static const kMessage = '전기차 기름차 응원하기';

  /// 오늘 한도를 다 채운 상태
  static const kDoneMessage = '오늘 응원 완료. 고맙습니다!';

  @override
  State<CheerStrip> createState() => _CheerStripState();
}

class _CheerStripState extends State<CheerStrip> {
  @override
  void initState() {
    super.initState();
    // 실패해도 조용히 넘어간다(응원 기능 원칙: 앱 사용 방해 금지) — 그때는
    // 카운트 없이 기본 문구만 나온다.
    CheerService.instance.preload();
  }

  void _open() {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const CheerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.supportBgDark : AppColors.supportBgLight;
    final fg = isDark ? AppColors.supportTextDark : AppColors.supportTextLight;

    // 콘솔 원격설정(cheer.home_strip)으로 통째로 끌 수 있다. status 응답 전에는
    // 마지막으로 알던 값(Hive 캐시)을 쓰므로 껐다 켠 뒤에도 번쩍임이 없다.
    return ValueListenableBuilder<bool>(
      valueListenable: CheerService.instance.homeStripNotifier,
      builder: (_, on, __) =>
          on ? _strip(isDark, bg, fg) : const SizedBox.shrink(),
    );
  }

  Widget _strip(bool isDark, Color bg, Color fg) {
    return ValueListenableBuilder<CheerStatus?>(
      valueListenable: CheerService.instance.statusNotifier,
      builder: (_, st, __) {
        // status 응답 전에는 **마지막으로 알던 오늘 횟수**(KST 날짜 확인 포함)를 쓴다.
        // 0 으로 시작하면 이미 3/3 을 채운 사람에게 '응원' 버튼이 한 번 떴다가
        // '오늘 만땅!' 으로 바뀌며 깜빡인다(형 제보).
        final svc = CheerService.instance;
        final today = st?.today ?? svc.cachedToday;
        final limit = st?.dailyLimit ?? svc.cachedDailyLimit;
        final done = today >= limit;
        // 콘솔 문구 오버라이드(cheer.home_strip_message / _done_message).
        // status 응답 전엔 캐시, 서버가 안 내리면(null) 아래 상수 폴백 — 어느 조합도
        // 빈 문구가 되지 않는다. 한 줄 제약은 FittedBox 가 흡수하지만 콘솔 저장
        // 단에서도 길이를 자른다.
        final message = st?.homeStripMessage ??
            svc.cachedHomeStripMessage ??
            CheerStrip.kMessage;
        final doneMessage = st?.homeStripDoneMessage ??
            svc.cachedHomeStripDoneMessage ??
            CheerStrip.kDoneMessage;

        return Padding(
          // 요약 카드(GasSummaryCard)와 같은 좌우 여백 · 세로 간격
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.volunteer_activism_rounded,
                      size: 20, color: AppColors.supportAccent),
                  const SizedBox(width: 9),
                  Expanded(
                    // 무조건 한 줄. 두 줄로 넘어가면 "…서버비가 / 됩니다" 처럼
                    // 어색하게 끊기고(형 제보), 말줄임은 문구를 조용히 잘라 먹는다.
                    // 320dp x1.2 같은 극단에서만 글자가 살짝 줄어들 뿐 잘리지 않는다.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        done ? doneMessage : message,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  // 오늘 다 채웠으면 눌러도 못 하는 버튼 대신 상태 표시
                  // (설정 진입 카드 `_cta` 와 같은 원칙).
                  if (done)
                    Text('오늘 만땅!',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: fg))
                  else
                    Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.supportAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        // 카운트(0/3)는 버튼에서 뺐다 — 문구가 밀려 두 줄이 되는
                        // 주범이었고, 남은 횟수는 응원 화면에서 바로 보인다.
                        '응원',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
