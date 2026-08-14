import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

/// 홈 상단 한 줄 헤더 — 왼쪽 주유/충전 탭, 오른쪽 위치 + 알림.
///
/// 기존의 `전기차 기름차` 타이틀 줄 + 캡슐 세그먼트 줄을 한 줄로 합쳤다.
///
/// 탭 규칙 3가지:
///  1. 활성 탭은 **글자와 언더바 모두** 모드색으로 물든다 (주유 파랑 / 충전 초록).
///  2. 터치 영역 46 고정 — 글자 크기만큼만 잡히면 안 된다.
///  3. 아이콘 없음. 글자만.
///
/// 언더바는 **Stack 으로 겹쳐** 그린다. Column 으로 쌓으면 글자가 언더바 높이만큼
/// 위로 밀려서 오른쪽 위치·알림과 세로 중심이 어긋난다(형 지적) — 겹쳐 그리면
/// 글자는 46 한가운데 그대로 있고 언더바만 아래에 붙는다.
/// 그래서 한 줄 안의 모든 요소를 **세로 중앙 정렬**로 둘 수 있다.
///
/// 캡슐 세그먼트에 있던 **길게 눌러 좌우 위치 바꾸기**는 이미 배포된 기능이라
/// 그대로 유지한다 — 순서는 Hive(keyHomeTabOrder)에 남는다.
class HomeTopHeader extends StatefulWidget {
  const HomeTopHeader({
    super.key,
    required this.activeIndex,
    required this.onChanged,
    required this.showTabs,
    required this.regionName,
    required this.hasUnread,
    required this.onBellTap,
    required this.onRegionTap,
  });

  /// 0 = 주유, 1 = 충전
  final int activeIndex;
  final ValueChanged<int> onChanged;

  /// 차량 타입이 '둘 다'일 때만 탭을 그린다. false 면 위치가 왼쪽으로 온다.
  final bool showTabs;

  /// 역지오코딩된 동 이름. null 이면 위치 묶음을 통째로 숨긴다.
  final String? regionName;

  final bool hasUnread;
  final VoidCallback onBellTap;

  /// 지역명을 누르면 **그 묶음의 화면 좌표**를 넘긴다 — 주소 팝업을 바텀시트가
  /// 아니라 지역명 바로 밑에 앵커시켜 띄우기 위해서다(형 지적).
  final ValueChanged<Rect> onRegionTap;

  /// 지금 **화면에 보이는** 탭 순서 — `[왼쪽 탭, 오른쪽 탭]` (0=주유, 1=충전).
  /// 길게 눌러 좌우를 바꾸면 Hive 에 남으므로 인덱스 순서와 다를 수 있다.
  /// 스와이프 방향 판정처럼 '화면 기준'이 필요한 곳에서 쓴다.
  static List<int> visualOrder() {
    try {
      final saved = Hive.box(AppConstants.settingsBox)
          .get(AppConstants.keyHomeTabOrder, defaultValue: 0) as int;
      return saved == 1 ? const [1, 0] : const [0, 1];
    } catch (_) {
      return const [0, 1];
    }
  }

  @override
  State<HomeTopHeader> createState() => _HomeTopHeaderState();
}

/// 탭 좌우 안쪽 패딩 — 언더바 길이는 `글자 폭 + 이 값 ×2` 가 된다(핸드오프 스펙).
const double _tabHPad = 7;

class _HomeTopHeaderState extends State<HomeTopHeader> {
  /// _order[i] = 위치 i 에 표시할 탭 인덱스 (0=주유, 1=충전)
  List<int> _order = HomeTopHeader.visualOrder();

  /// 주소 팝업을 이 묶음 바로 아래에 앵커시키려고 좌표를 재는 용도.
  final GlobalKey _regionKey = GlobalKey();

  void _swap() {
    setState(() => _order = [_order[1], _order[0]]);
    Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyHomeTabOrder, _order[0]);
  }

  /// 드롭 → 위치 swap + 드래그한 탭을 활성으로 (기존 캡슐 동작 그대로).
  void _onDropFrom(int draggedFromPos) {
    final draggedTabIdx = _order[draggedFromPos];
    HapticFeedback.selectionClick();
    _swap();
    if (widget.activeIndex != draggedTabIdx) widget.onChanged(draggedTabIdx);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      // 스펙의 헤더 내부 세로 간격은 10 이고, 검색줄이 자기 상단 패딩 4 를
      // 이미 갖고 있으므로 여기선 6 만 준다. 0 이던 시절엔 언더바가 검색바에
      // 거의 닿았고, 8 을 빈 여백으로 얹었을 땐 검색바가 떠 보였다(형 지적).
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.showTabs) ...[
            // 탭 사이 간격 4 — 각 탭이 좌우 7 패딩을 갖고 있어 시각 간격은 ≈18.
            _tabAt(0, isDark),
            const SizedBox(width: 4),
            _tabAt(1, isDark),
          ],
          // Spacer + Flexible 을 나란히 두면 둘이 남는 폭을 나눠 가져서 위치와
          // 알림 사이에 빈 틈이 생긴다. 남는 폭을 Expanded 하나가 다 먹고
          // 그 안에서 오른쪽 정렬 + ellipsis 로 처리한다.
          Expanded(
            child: Row(
              mainAxisAlignment: widget.showTabs
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [Flexible(child: _regionChunk(isDark))],
            ),
          ),
          _bell(isDark),
        ],
      ),
    );
  }

  // ── 탭 ──────────────────────────────────────────────────────────
  Widget _tabAt(int pos, bool isDark) {
    final tabIdx = _order[pos];
    return LongPressDraggable<int>(
      data: pos,
      delay: const Duration(milliseconds: 250),
      feedback: Material(
        color: Colors.transparent,
        child: _tabLabel(tabIdx, active: true, isDark: isDark, scale: 1.06),
      ),
      childWhenDragging:
          Opacity(opacity: 0.35, child: _tab(tabIdx, isDark, false)),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != pos,
        onAcceptWithDetails: (d) => _onDropFrom(d.data),
        builder: (_, candidates, __) =>
            _tab(tabIdx, isDark, candidates.isNotEmpty),
      ),
    );
  }

  Widget _tab(int tabIdx, bool isDark, bool highlight) {
    final active = widget.activeIndex == tabIdx;
    final accent = tabIdx == 1 ? AppColors.evGreen : AppColors.gasBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (active) return;
        HapticFeedback.selectionClick();
        widget.onChanged(tabIdx);
      },
      child: SizedBox(
        // 글자만 남기면 터치 영역이 글자 크기로 줄어든다. 46 확보.
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 언더바를 Column 으로 쌓으면 글자가 그만큼 위로 밀려서, 오른쪽
            // 위치·알림과 세로 중심이 어긋난다(형 지적). Stack 으로 겹쳐 그리면
            // 글자는 46 한가운데 그대로 있고 언더바만 바닥에 붙는다 —
            // 스펙의 `Column(mainAxisAlignment: end)` 배치와 결과가 같다.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _tabHPad),
              child:
                  _tabLabel(tabIdx, active: active || highlight, isDark: isDark),
            ),
            // 언더바는 글자 폭 + 좌우 7 (left/right 0 → Stack 폭 전체).
            // 박스 바닥에 붙이면 글자 박스 하단(34)과 정확히 9 가 떨어진다.
            // 예전엔 bottom 7 이라 글자에 달라붙어 밑줄처럼 보였다(형 지적).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: active ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabLabel(int tabIdx,
      {required bool active, required bool isDark, double scale = 1.0}) {
    final accent = tabIdx == 1 ? AppColors.evGreen : AppColors.gasBlue;
    final inactive =
        isDark ? AppColors.homeTabInactiveDark : AppColors.homeTabInactiveLight;
    return Transform.scale(
      scale: scale,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        style: TextStyle(
          fontSize: 22,
          // 스펙 고정값. height 를 안 주면 Pretendard 기본 행높이(≈1.27)로
          // 글자 박스가 28 까지 부풀어, 46 안에서 언더바를 바닥에 붙여도
          // 간격이 3~4 밖에 안 남아 밑줄처럼 붙어 보인다(형 지적).
          // 1.0 은 글리프를 누르는 게 아니라 행 박스만 22 로 맞추는 것 —
          // 글자 모양은 그대로고, 박스 하단↔언더바가 정확히 9 가 된다.
          height: 1.0,
          letterSpacing: -0.66,
          fontWeight: active ? FontWeight.w800 : FontWeight.w700,
          color: active ? accent : inactive,
        ),
        child: Text(tabIdx == 1 ? '충전' : '주유'),
      ),
    );
  }

  // ── 위치 (핀 + 동 이름) ─────────────────────────────────────────
  Widget _regionChunk(bool isDark) {
    final name = widget.regionName;
    if (name == null) return const SizedBox.shrink();
    // 핀은 활성 모드 색을 따른다 — 검색 정렬칩·필터칩·FAB 가 전부 모드색이라
    // 여기만 고정색이면 충전 탭에서 혼자 튄다(알림 벨과 같은 이유).
    final accent =
        widget.activeIndex == 1 ? AppColors.evGreen : AppColors.gasBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final box = _regionKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        widget.onRegionTap(box.localToGlobal(Offset.zero) & box.size);
      },
      child: Row(
        key: _regionKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_rounded, size: 17, color: accent),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
          ),
          Icon(Icons.expand_more_rounded,
              size: 17,
              color:
                  isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
        ],
      ),
    );
  }

  // ── 알림 ────────────────────────────────────────────────────────
  Widget _bell(bool isDark) {
    final base =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    // 미확인 강조는 활성 모드 색을 따른다 — 구 헤더에서 넘어온 gasBlue 고정이라
    // 충전 탭에서도 벨만 파랗게 남아 있었다.
    final accent =
        widget.activeIndex == 1 ? AppColors.evGreen : AppColors.gasBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onBellTap,
      child: SizedBox(
        // iOS HIG·Material 최소 터치 타깃 44.
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              widget.hasUnread
                  ? Icons.notifications_rounded
                  : Icons.notifications_none_rounded,
              size: 22,
              color: widget.hasUnread ? accent : base,
            ),
            if (widget.hasUnread)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.darkBg : Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
