import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/services/regular_station_service.dart';
import '../../data/services/station_alias_service.dart';
import '../widgets/shared_widgets.dart';
import 'widgets/level_basis_card.dart';

const _kPrimary = Color(0xFF3B82F6); // 주유=파랑 단일 축 (형 확정 6a — 색 3축이 짜쳐 보임)
const _kPrimaryLight = Color(0xFFEFF6FF);
const _kSelected = Color(0xFF2563EB); // 사용자가 고른 대안 — 같은 파랑 축의 짙은 톤
const _kSelectedLight = Color(0xFFEAF2FF);
// 다른 후보 섹션 — 중립 슬레이트 톤 (보라 폐기: 색은 파랑 축 하나만).
const _kAltBg = Color(0xFFF7F9FB); // 카드 컨테이너 배경
const _kAltBorder = Color(0xFFE5EAF0); // 카드 컨테이너 border
const _kAltBadgeBg = Color(0xFFEDF1F5); // 일반 alt 번호 배지 배경
const _kAltBadgeText = Color(0xFF64748B); // 일반 alt 번호 배지 글자
// 닿기 어려움 — 빨강 경고 대신 뮤트 슬레이트로 가라앉혀 고급스럽게(마커와 통일).
const _kUnreachableBg = Color(0xFFF6F8FA); // row 배경 (옅은 슬레이트)
const _kUnreachableChipBg = Color(0xFFE7ECF1); // 칩/배지 배경
const _kUnreachableAccent = Color(0xFF8A96A3); // 뮤트 슬레이트 (아이콘·텍스트)

/// CommonMark의 right-flanking 규칙상 `**X**` 의 닫는 `**` 뒤에 한글 음절이 오면
/// emphasis 종료를 인식하지 못해 raw 마커가 그대로 노출된다 (예: `**22%**로`).
/// 시각적 영향이 없는 ZWSP(U+200B)를 끼워 word boundary 역할을 부여 → flutter_markdown 이 정상 파싱.
/// (직접 `**` 를 파싱하는 게 아니라 라이브러리가 인식할 수 있게 입력만 정규화.)
String _normalizeMarkdownForKorean(String src) {
  final zwsp = String.fromCharCode(0x200B);
  // 1) "** 텍스트 **" 처럼 구분자 안쪽에 공백이 있으면 CommonMark 가 볼드로 안 봄(원시 ** 노출)
  //    → 안쪽 가장자리 공백 제거.
  var s = src.replaceAllMapped(
    RegExp(r'\*\*[ \t]*([^*\n]+?)[ \t]*\*\*'),
    (m) => '**${m.group(1)!}**',
  );
  // 2) 닫는 ** 앞이 문장부호(%,/ 등)이고 바로 뒤가 한글이면 파싱 실패(예: **25%**로)
  //    → 닫는 ** "앞"에 ZWSP 삽입해 부호 플랭킹 회피. (ZWSP 비표시 → 기존 케이스 영향 없음)
  s = s.replaceAllMapped(
    RegExp(r'\*\*([^\n*][^\n*]*?)\*\*(?=[가-힣])'),
    (m) => '**${m.group(1)!}$zwsp**',
  );
  return s;
}

// 통일된 색상 체계
const _kMarkerRecommend = Color(0xFF3B82F6); // 추천 (파랑 — 주황 폐기)
const _kMarkerRecommendLight = Color(0xFFEFF6FF); // 추천 배경 (연한 파랑)

/// 직행 대비 추가 시간이 0분이면 '우회 없음', 1분부터 '우회'.
const int _kDetourStartMinutes = 1;

int? _detourMinutesForUi(num? detourTimeMin) {
  if (detourTimeMin == null) return null;
  final m = detourTimeMin.ceil();
  return m < 0 ? 0 : m;
}

bool _detourIsNegligible(
    {required int detourM,
    required num? detourTimeMin,
    bool? serverDetourIsNone}) {
  if (serverDetourIsNone != null) return serverDetourIsNone;
  final m = _detourMinutesForUi(detourTimeMin);
  if (m != null) return m < _kDetourStartMinutes;
  return detourM <= 500;
}

int? _meaningfulDetourMinutes(num? detourTimeMin, {bool? serverDetourIsNone}) {
  if (serverDetourIsNone == true) return null;
  final m = _detourMinutesForUi(detourTimeMin);
  if (m == null || m < _kDetourStartMinutes) return null;
  return m;
}

String _detourAltListSubtitle(
    {required int detourM,
    required num? detourTimeMin,
    bool? serverDetourIsNone}) {
  if (_detourIsNegligible(
      detourM: detourM,
      detourTimeMin: detourTimeMin,
      serverDetourIsNone: serverDetourIsNone)) return '우회 없음';
  final m = _meaningfulDetourMinutes(detourTimeMin,
      serverDetourIsNone: serverDetourIsNone);
  if (m != null && m > 0) return '약 ${fmtMin(m)} 우회';
  if (detourM >= 1000) return '${(detourM / 1000).toStringAsFixed(1)}km 우회';
  if (detourM > 0) return '${detourM}m 우회';
  return '조금 우회';
}

/// `DraggableScrollableSheet`용 스크롤 컨트롤러가 붙은 영역에 포함되어야 핸들 드래그로 시트가 움직인다.
class _PinnedSheetHandleDelegate extends SliverPersistentHeaderDelegate {
  static const double extent = 24; // margin 10 + bar 4 + margin 10

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? AppColors.darkBg : Colors.white,
      child: Align(
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkTextMuted : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

// ─── 결과 화면 (독립 페이지로 push 할 때) ─────────────────────────────────────

class AiResultScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final String? routeSummary;
  final double originLat;
  final double originLng;
  final List<Map<String, dynamic>> pathPoints;

  const AiResultScreen({
    super.key,
    required this.data,
    required this.destinationName,
    this.routeSummary,
    this.originLat = 0,
    this.originLng = 0,
    this.pathPoints = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : Colors.white;
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a);
    final subtitleColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF999999);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: titleColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('분석 결과',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: titleColor)),
            if (routeSummary != null)
              Text(routeSummary!,
                  style: TextStyle(fontSize: 12, color: subtitleColor)),
          ],
        ),
      ),
      body: AiResultBody(
        data: data,
        destinationName: destinationName,
        originLat: originLat,
        originLng: originLng,
      ),
    );
  }
}

// ─── 결과 Body ──────────────────────────────────────────────────────────────

class AiResultBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final double originLat;
  final double originLng;
  final ScrollController? scrollController;
  final String? fuelLabel;

  /// 대안 "확인" 탭 시 지도 업데이트 (서버 `via_route` 포함 시 그대로 사용)
  final void Function(Map<String, dynamic> altItem)? onAltRouteView;

  /// 대안 선택 취소 → AI 추천으로 복원 콜백
  final VoidCallback? onResetToAiRec;

  /// 고속도로 필터를 끄고(저장 포함) 같은 조건으로 즉시 재분석
  /// (highway_filter.applied 배너의 "필터 끄고 재조회" 액션)
  final VoidCallback? onDisableHighwayAndRetry;

  /// 이 결과가 계산된 기준 잔량 % — 상단 기준 칩으로 상시 노출
  final double? levelPercent;

  /// 1%당 주행가능 km (용량 × 효율 / 100) — 칩의 km 환산용
  final double? kmPerPercent;

  /// 기준 칩 탭 → 잔량 시트 → 저장 시 재추천
  final VoidCallback? onEditLevel;

  const AiResultBody({
    super.key,
    required this.data,
    required this.destinationName,
    this.originLat = 0,
    this.originLng = 0,
    this.scrollController,
    this.fuelLabel,
    this.onAltRouteView,
    this.onResetToAiRec,
    this.onDisableHighwayAndRetry,
    this.levelPercent,
    this.kmPerPercent,
    this.onEditLevel,
  });

  @override
  State<AiResultBody> createState() => _AiResultBodyState();
}

class _AiResultBodyState extends State<AiResultBody> {
  /// 사용자가 대안에서 선택한 아이템 (null = AI 추천 유지)
  Map<String, dynamic>? _selectedAltItem;

  /// 대안 선택 시 표시할 커스텀 AI 메시지
  String? _altAiMessage;

  static final _wonFmt = NumberFormat('#,###', 'ko_KR');

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  void _selectAlt(dynamic altItem) {
    if (altItem == null) {
      // 선택 취소 → AI 추천으로 복원
      setState(() {
        _selectedAltItem = null;
        _altAiMessage = null;
      });
      widget.onResetToAiRec?.call();
      return;
    }
    if (altItem is! Map) return;
    final st = altItem['station'];
    if (st is! Map) return;
    final lat = _d(st['lat']);
    final lng = _d(st['lng']);
    if (lat == null || lng == null) return;
    final name = st['name']?.toString() ?? '';
    final price = _d(st['price_won_per_liter'])?.round() ?? 0;
    setState(() {
      _selectedAltItem = Map<String, dynamic>.from(altItem);
      _altAiMessage = _buildAltMessage(altItem, name, price);
    });
    widget.onAltRouteView?.call(Map<String, dynamic>.from(altItem));
  }

  // 상세 비교표 — 추천/경로상/우회/대안 후보 전부를 가격순 카드로 팝업.
  void _showComparisonDetailSheet() {
    final d = widget.data;
    final rec = d['recommendation'] is Map ? d['recommendation'] as Map : null;
    final choice = rec?['choice']?.toString();
    final ca = (rec?['decision_trace'] is Map &&
            (rec!['decision_trace'] as Map)['cost_analysis'] is Map)
        ? Map<String, dynamic>.from(
            (rec['decision_trace'] as Map)['cost_analysis'] as Map)
        : null;

    Map<String, dynamic>? toCard(dynamic item, String role, bool isRec) {
      if (item is! Map) return null;
      final st = item['station'];
      if (st is! Map) return null;
      final price = _d(st['price_won_per_liter']);
      if (price == null) return null;
      final isNone = item['detour_is_none'] == true;
      return {
        'name': _stationNameFrom(Map<String, dynamic>.from(st)),
        'brand': st['brand']?.toString(),
        'price': price,
        'detour': isNone ? 0 : _i(item['detour_time_min']),
        'cost': _i(item['expected_cost_won']),
        'savings': _fuelSavingsWon(item),
        'role': role,
        'isRec': isRec,
      };
    }

    final cards = <Map<String, dynamic>>[];
    Map<String, dynamic>? sheetCost = ca;
    if (_selectedAltItem != null) {
      // 대안 선택 시: AI 추천 vs 내가 선택한 곳 + 그 둘의 비용 판정 박스.
      final aiRecItem =
          choice == 'best_detour' ? d['best_detour'] : d['on_route'];
      final aiCard = toCard(aiRecItem, 'AI 추천', false);
      final selCard = toCard(_selectedAltItem, '선택됨', false);
      if (aiCard != null) cards.add(aiCard);
      if (selCard != null) cards.add(selCard);
      final sel = _selectedAltItem!;
      final rawSav = _i(sel['savings_vs_primary_won']);
      final netSav =
          sel['real_savings_won'] is num ? _i(sel['real_savings_won']) : rawSav;
      sheetCost = {
        'savings_won': rawSav,
        'price_diff_won': rawSav, // savings_vs_primary_won은 클램프 없음 — 그대로 원시 가격차
        'subject': '선택한 곳',
        'detour_cost_won': rawSav - netSav,
        'net_benefit_won': netSav,
        'detour_fuel_won':
            sel['detour_fuel_won'] is num ? _i(sel['detour_fuel_won']) : null,
        'detour_extra_min':
            sel['detour_extra_min'] is num ? _i(sel['detour_extra_min']) : null,
        'verdict': netSav >= 0 ? 'detour_worth' : 'on_route_worth',
      };
    } else {
      final isRanked = d['recommendation'] is Map &&
          (d['recommendation'] as Map)['card_mode'] == 'ranked';
      final onR =
          toCard(d['on_route'], isRanked ? '추천' : '경로상', choice == 'on_route');
      if (onR != null) cards.add(onR);
      final det = toCard(
          d['best_detour'], isRanked ? '차선' : '우회', choice == 'best_detour');
      if (det != null) cards.add(det);
      if (onR == null &&
          d['alternatives'] is List &&
          (d['alternatives'] as List).isNotEmpty) {
        final alt = toCard((d['alternatives'] as List).first, '우회', false);
        if (alt != null && alt['name'] != det?['name']) cards.add(alt);
      }
    }
    if (cards.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ComparisonDetailSheet(
          cards: cards, cost: sheetCost, wonFmt: _wonFmt),
    );
  }

  String _buildAltMessage(Map altItem, String name, int price) {
    final detourM = _i(altItem['detour_distance_m']);
    // 실질 절약(부가비용 뺀) 우선, 없으면 단순 절약 폴백.
    final savings = _fuelSavingsWon(altItem);
    final detourTimeMin = altItem['detour_time_min'] is num
        ? altItem['detour_time_min'] as num
        : null;
    final detourIsNone = altItem['detour_is_none'] is bool
        ? altItem['detour_is_none'] as bool
        : null;
    final String detourText;
    if (_detourIsNegligible(
        detourM: detourM,
        detourTimeMin: detourTimeMin,
        serverDetourIsNone: detourIsNone)) {
      detourText = '우회 없음(직행과 비슷한 소요)';
    } else {
      final m = _meaningfulDetourMinutes(detourTimeMin,
          serverDetourIsNone: detourIsNone);
      if (m != null && m > 0) {
        detourText = '약 ${fmtMin(m)} 우회';
      } else if (detourM >= 1000) {
        detourText = '${(detourM / 1000).toStringAsFixed(1)}km 우회 필요';
      } else {
        detourText = '${detourM}m 우회 필요';
      }
    }

    final lines = <String>[
      '$name을 선택하셨습니다.',
      '리터당 ${_wonFmt.format(price)}원, $detourText.',
    ];
    if (savings > 0) {
      lines.add('AI 추천 경로 대비 ${_wonFmt.format(savings)}원 절약됩니다.');
    } else if (savings < 0) {
      lines.add('AI 추천 경로보다 ${_wonFmt.format(-savings)}원 더 비쌉니다.');
    }
    return lines.join('\n');
  }

  /// 이 위젯의 build 는 `DraggableScrollableSheet` 의 LayoutBuilder 안,
  /// 즉 **레이아웃 단계**에서 돌아간다. 그 안에서 예외가 나면 Flutter 가
  /// ErrorWidget 조차 끼우지 못하고 서브트리를 통째로 비워버려서, 화면엔
  /// 아무 안내도 없이 **흰 시트만** 남는다(형 제보 2026-08-19 — 팝업엔 추천이
  /// 정상적으로 떴는데 상세 시트만 백지).
  /// 추천 결과가 통째로 사라지는 것보다, 못 그린 이유가 보이는 편이 낫다.
  @override
  Widget build(BuildContext context) {
    try {
      return _buildSheet(context);
    } catch (e, st) {
      debugPrint('[AiResultBody] 렌더 실패: $e\n$st');
      return _buildRenderFailure(context, e);
    }
  }

  /// build 가 실패했을 때의 대체 화면 — 시트 드래그는 그대로 살리고,
  /// 최소한의 추천 정보 + 실패 원인을 보여준다(제보용으로 그대로 캡처 가능).
  /// 추천 조건 안내 한 줄 — 라벨 칩 + 문장 (형 시안 2c).
  ///
  /// 예전엔 앰버 박스 + 아이콘이었는데, 이건 경고가 아니라 "어떤 기준으로 골랐는지"
  /// 설명이다. 노란 경고톤이 결과 카드 위에서 시각 소음이 커서 박스를 지우고
  /// 라벨 + 본문 텍스트만 남긴다.
  Widget _noteRow(bool isDark,
      {required String label, required String text, Widget? trailing}) {
    final chipBg = isDark
        ? AppColors.darkBlueBright.withValues(alpha: 0.16)
        : const Color(0xFFE8F0FE);
    final chipFg = isDark ? AppColors.darkBlueBright : const Color(0xFF2563EB);
    final bodyFg =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF334155);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 칩은 첫 줄 높이에 맞춰 살짝 내린다 — 본문이 여러 줄이어도 위에 붙어 있게.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: chipFg)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, height: 1.45, color: bodyFg)),
            ),
          ],
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildRenderFailure(BuildContext context, Object error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark ? AppColors.darkAmberBright : const Color(0xFF8A6D3B);
    String? name;
    String? price;
    try {
      final d = widget.data;
      for (final k in const ['on_route', 'best_detour']) {
        final slot = d[k];
        if (slot is Map && slot['station'] is Map) {
          final st = slot['station'] as Map;
          name = st['display_name']?.toString().trim().isNotEmpty == true
              ? st['display_name'].toString()
              : st['name']?.toString();
          final p = st['price_won_per_liter'];
          if (p is num) price = '${_wonFmt.format(p.round())}원/L';
          if (name != null && name.isNotEmpty) break;
        }
      }
    } catch (_) {}

    final children = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkAmberBright.withValues(alpha: 0.14)
              : const Color(0xFFFFF9E8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark
                  ? AppColors.darkAmberBright.withValues(alpha: 0.35)
                  : const Color(0xFFFFE6A6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('추천 상세를 표시하지 못했어요. 지도의 추천 마커는 정상이에요.',
                      style: TextStyle(
                          fontSize: 13, color: amber, height: 1.4)),
                ),
              ],
            ),
            if (name != null && name.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : const Color(0xFF1a1a1a))),
              if (price != null)
                Text(price,
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : const Color(0xFF64748B))),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {}),
                icon: Icon(Icons.refresh_rounded, size: 15, color: amber),
                label: Text('다시 시도',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: amber)),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 제보용 — 이 줄만 캡처해 주면 원인이 바로 나온다.
      Text('오류: $error',
          style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: isDark
                  ? AppColors.darkTextMuted
                  : const Color(0xFF999999))),
    ];

    if (widget.scrollController != null) {
      return CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverPersistentHeader(
              pinned: true, delegate: _PinnedSheetHandleDelegate()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: children,
    );
  }

  Widget _buildSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = widget.data;
    final computed = data['computed'] is Map
        ? data['computed'] as Map<String, dynamic>
        : null;
    final reachable = computed?['reachable'] is Map
        ? computed!['reachable'] as Map<String, dynamic>
        : null;
    final onRoute = data['on_route'] is Map
        ? data['on_route'] as Map<String, dynamic>
        : null;
    final bestDetour = data['best_detour'] is Map
        ? data['best_detour'] as Map<String, dynamic>
        : null;
    final rec = data['recommendation'] is Map
        ? data['recommendation'] as Map<String, dynamic>
        : null;
    final nav = data['navigation'] is Map
        ? data['navigation'] as Map<String, dynamic>
        : null;
    final dest = nav?['destination'] is Map
        ? nav!['destination'] as Map<String, dynamic>
        : null;

    final choice = rec?['choice']?.toString() ?? 'on_route';
    final cardMode = rec?['card_mode']?.toString() ?? 'normal';
    final isDualDetour = cardMode == 'dual_detour';
    // 통합 랭킹 프레임 — on_route 슬롯=추천 1위, best_detour 슬롯=차선 2위 (수신 시 치환됨).
    // 경로상/우회 라벨 대신 추천/차선으로 표기 ("경로상인데 +3분" 라벨-실측 역전 혼란 해소).
    final isRankedMode = cardMode == 'ranked';
    // 서버가 2번째 카드 노출 여부 결정 (추천보다 비싸기만 한 우회는 숨김). 누락 시 기본 표시.
    final showSecondary = rec?['show_secondary'] != false;
    // 서버가 경로상 후보 없을 때 최소 우회시간 후보를 가상 baseline 으로 승격
    // → "경로상 최저가" 라벨을 "근거리 우회"로 분기
    final isOnRouteVirtual = onRoute?['is_on_route_virtual'] == true;
    final onRouteLabel =
        isRankedMode ? '추천' : (isOnRouteVirtual ? '근거리 우회' : '경로상 최저가');
    final uiMessage = _altAiMessage ?? rec?['ui_message']?.toString() ?? '';

    final onRouteSt = onRoute?['station'] is Map
        ? onRoute!['station'] as Map<String, dynamic>
        : null;
    final detourSt = bestDetour?['station'] is Map
        ? bestDetour!['station'] as Map<String, dynamic>
        : null;

    final destLat = _d(dest?['lat']);
    final destLng = _d(dest?['lng']);
    final goalL = _d(computed?['goal_liters']);

    // on_route 데이터
    final orLat = _d(onRouteSt?['lat']);
    final orLng = _d(onRouteSt?['lng']);
    final orPrice = _d(onRouteSt?['price_won_per_liter']);
    final orCost = _i(onRoute?['expected_cost_won']);
    final orDetourM = _i(onRoute?['detour_distance_m']);
    final orDetourTimeMin = (onRoute?['detour_is_none'] == true)
        ? 0
        : (onRoute?['detour_time_min'] is num
            ? onRoute!['detour_time_min'] as num
            : null);

    // best_detour 데이터
    final dtLat = _d(detourSt?['lat']);
    final dtLng = _d(detourSt?['lng']);
    final dtPrice = _d(detourSt?['price_won_per_liter']);
    final dtCost = _i(bestDetour?['expected_cost_won']);
    final dtDetourM = _i(bestDetour?['detour_distance_m']);
    final dtDetourTimeMin = (bestDetour?['detour_is_none'] == true)
        ? 0
        : (bestDetour?['detour_time_min'] is num
            ? bestDetour!['detour_time_min'] as num
            : null);
    // 배너 '더 소요'는 우회−경로상 상대 시간차 (절대 우회시간 X). 역전/동일이면 null(숨김).
    final int? dtTimeMinsBanner;
    if (orDetourTimeMin != null && dtDetourTimeMin != null) {
      final diff = (dtDetourTimeMin - orDetourTimeMin).round();
      dtTimeMinsBanner = diff > 0 ? diff : null;
    } else {
      dtTimeMinsBanner = _meaningfulDetourMinutes(dtDetourTimeMin);
    }
    // 연료 기준 절약(시간값 제외). 음수면 0 처리(카드엔 '절약'만, 상세표에서 확인).
    final _rsDt = bestDetour is Map ? _fuelSavingsWon(bestDetour as Map) : 0;
    final dtSavings = _rsDt > 0 ? _rsDt : 0;

    // 서버가 best_detour를 보냈으면 비교표에 항상 노출 (가격 우열은 추천 로직이 결정).
    // 우회가 더 비싸도 "왜 우회 칸이 비었지?" 혼동 방지 — 서버 commit 1dee302 의도와 정합.
    final showDetour = detourSt != null;

    // 단골 비교 — 단골이 이번 추천 후보군에 실제로 포함됐을 때만 내려온다.
    // 표시 규칙(설계서 §6): 1순위 카드에만, diff 0 이면 줄 자체 생략.
    final regularCompare =
        data['regular_compare'] is Map ? data['regular_compare'] as Map : null;
    final regMatched = regularCompare?['matched'] == true;
    final regIsPrimary = regMatched && regularCompare?['is_primary'] == true;
    final regDiffRaw = regularCompare?['approx_diff_won'];
    final int? regDiffWon =
        (regMatched && !regIsPrimary && regDiffRaw is num && regDiffRaw > 0)
            ? regDiffRaw.round()
            : null;
    // 1·2순위가 모두 내 단골인 경우 — 문구를 "두 곳 다 단골" 로 바꾼다.
    final regSecondAlsoMine = regularCompare?['second_is_regular'] == true;
    // 서버가 고른 비교 대상 1곳(station_id)의 이름을 로컬 단골 목록에서 찾는다
    // (복수 단골 — 어느 단골과 비교했는지 문구에 정확히 쓴다).
    final regName = regularCompare?['station_id'] == null
        ? null
        : RegularStationService.byId(
                regularCompare!['station_id'].toString())
            ?.name;

    final hasOverride = _selectedAltItem != null;
    // 서버 choice가 누락/불일치여도 on_route가 비어 있고 detour가 있으면 detour를 메인으로 강제
    final forceDetourAsPrimary =
        !isDualDetour && onRouteSt == null && detourSt != null;
    final aiRecIsDetour = isDualDetour ||
        forceDetourAsPrimary ||
        (choice == 'best_detour' && showDetour);
    final noStationToRecommend = onRouteSt == null && detourSt == null;

    // ── Primary 카드 (상단) 계산
    _CardInfo primary;
    if (hasOverride) {
      final ovSt = _selectedAltItem!['station'] is Map
          ? Map<String, dynamic>.from(_selectedAltItem!['station'] as Map)
          : <String, dynamic>{};
      primary = _CardInfo(
        name: _stationNameFrom(ovSt),
        addr: ovSt['address']?.toString(),
        lat: _d(ovSt['lat']),
        lng: _d(ovSt['lng']),
        price: _d(ovSt['price_won_per_liter']),
        cost: _i(_selectedAltItem!['expected_cost_won']),
        detourM: _i(_selectedAltItem!['detour_distance_m']),
        detourTimeMin: _selectedAltItem!['detour_time_min'] is num
            ? ((_selectedAltItem!['detour_is_none'] == true)
                ? 0
                : _selectedAltItem!['detour_time_min'] as num)
            : null,
        savings: 0,
        tag: '선택됨',
        tagColor: _kSelected,
        isAiRec: false,
        isUserSelected: true,
        stationId: ovSt['id']?.toString(),
        brandCode: ovSt['brand']?.toString(),
      );
    } else if (aiRecIsDetour) {
      primary = _CardInfo(
        name: _stationNameFrom(detourSt),
        addr: detourSt?['address']?.toString(),
        lat: dtLat,
        lng: dtLng,
        price: dtPrice,
        cost: dtCost,
        detourM: dtDetourM,
        detourTimeMin: dtDetourTimeMin,
        savings: dtSavings,
        tag: isDualDetour ? '추천' : '우회 최저가',
        tagColor:
            isDualDetour ? const Color(0xFF1D9E75) : const Color(0xFF1D6FE0),
        isAiRec: true,
        isUserSelected: false,
        rawData: bestDetour,
        stationId: detourSt?['id']?.toString(),
        brandCode: detourSt?['brand']?.toString(),
      );
    } else {
      primary = _CardInfo(
        name: _stationNameFrom(onRouteSt),
        addr: onRouteSt?['address']?.toString(),
        lat: orLat,
        lng: orLng,
        price: orPrice,
        cost: orCost,
        detourM: orDetourM,
        detourTimeMin: orDetourTimeMin,
        savings: 0,
        tag: onRouteLabel,
        tagColor: const Color(0xFF3B82F6), // 파랑 (주황 폐기)
        isAiRec: true,
        isUserSelected: false,
        rawData: onRoute,
        stationId: onRouteSt?['id']?.toString(),
        brandCode: onRouteSt?['brand']?.toString(),
      );
    }

    // ── Secondary 카드 (하단 참고용) 계산
    _CardInfo? secondary;
    if (hasOverride) {
      // 오버라이드 시: AI 추천을 참고용으로 표시
      if (aiRecIsDetour) {
        secondary = _CardInfo(
          name: _stationNameFrom(detourSt),
          addr: detourSt?['address']?.toString(),
          lat: dtLat,
          lng: dtLng,
          price: dtPrice,
          cost: dtCost,
          detourM: dtDetourM,
          detourTimeMin: dtDetourTimeMin,
          savings: dtSavings,
          tag: 'AI 추천',
          tagColor: _kPrimary,
          isAiRec: false,
          isUserSelected: false,
        );
      } else if (onRouteSt != null) {
        secondary = _CardInfo(
          name: _stationNameFrom(onRouteSt),
          addr: onRouteSt['address']?.toString(),
          lat: orLat,
          lng: orLng,
          price: orPrice,
          cost: orCost,
          detourM: orDetourM,
          detourTimeMin: orDetourTimeMin,
          savings: 0,
          tag: 'AI 추천',
          tagColor: _kPrimary,
          isAiRec: false,
          isUserSelected: false,
        );
      }
    } else if (aiRecIsDetour && onRouteSt != null && showSecondary) {
      // 우회 AI 추천 → 경로상 최저가(또는 dual_detour 모드의 2순위)를 하단 참고로
      secondary = _CardInfo(
        name: _stationNameFrom(onRouteSt),
        addr: onRouteSt['address']?.toString(),
        lat: orLat,
        lng: orLng,
        price: orPrice,
        cost: orCost,
        detourM: orDetourM,
        detourTimeMin: orDetourTimeMin,
        savings: 0,
        tag: isDualDetour ? '차선' : onRouteLabel,
        tagColor:
            isDualDetour ? const Color(0xFF888888) : const Color(0xFF3B82F6),
        isAiRec: false,
        isUserSelected: false,
        rawData: onRoute,
      );
    } else if (!aiRecIsDetour && showDetour && showSecondary) {
      // 경로 AI 추천 → 더 싼 우회 최저가를 하단 참고로 (서버가 더 쌀 때만 show_secondary=true)
      secondary = _CardInfo(
        name: _stationNameFrom(detourSt),
        addr: detourSt['address']?.toString(),
        lat: dtLat,
        lng: dtLng,
        price: dtPrice,
        cost: dtCost,
        detourM: dtDetourM,
        detourTimeMin: dtDetourTimeMin,
        savings: dtSavings,
        tag: isRankedMode ? '차선' : '우회 최저가',
        tagColor: isRankedMode
            ? const Color(0xFF888888)
            : const Color(0xFF1D6FE0), // 파랑
        isAiRec: false,
        isUserSelected: false,
        rawData: bestDetour,
      );
    }

    // 기준 안내 줄 — 카드 안에 담는다(형 제보 2026-08-20: 카드 밖에 떠 있으면
    // 추천과 잔량 편집 사이에 끼어 보인다). 위젯 생성 코드는 그대로 재사용.
    final basisNotes = <Widget>[
      // 선호 브랜드 폴백 안내 — 고른 브랜드가 경로에 없어 전체에서 추천한 경우.
      // 연료 범위·경로 유형과 같은 계열(고른 기준 설명)이라 같은 라벨 + 문장으로.
      if (rec?['brand_filter'] is Map &&
          (rec!['brand_filter'] as Map)['fallback'] == true)
        _noteRow(isDark,
            label: '선호 브랜드',
            text: '선택한 선호 브랜드가 이 경로엔 없어 전체 주유소에서 추천했어요'),
      // 고속도로 필터 안내 — 서버 highway_filter 신호(additive, 구서버는 필드 없음 → 미표시).
      //  · fallback: 들를 휴게소가 없어 서버가 필터를 무시하고 일반 추천으로 폴백함 — 안내만.
      //  · applied: 휴게소 모드로 추천됨 — 안내 + "필터 끄고 재조회" 액션.
      // 경고가 아니라 '무슨 기준으로 골랐는지' 설명이라 라벨 + 문장으로 (형 시안 2c).
      if (rec?['highway_filter'] is Map &&
          ((rec!['highway_filter'] as Map)['fallback'] != null ||
              (rec['highway_filter'] as Map)['applied'] == true))
        Builder(builder: (_) {
          final hwf = rec['highway_filter'] as Map;
          final fb = hwf['fallback']?.toString();
          final hasWarning = hwf['warning'] != null;
          final msg = fb != null
              ? (fb == 'rest_stops_unreachable'
                  ? '경로상 휴게소는 모두 우회가 커서 일반 주유소에서 추천했어요'
                  : '경로가 고속도로를 지나지 않아 일반 주유소에서 추천했어요')
              : (hasWarning
                  ? '경로상 휴게소가 모두 우회가 커요. 필터를 끄면 더 나은 추천을 받을 수 있어요'
                  : '고속도로 필터가 켜져 있어 휴게소 주유소에서만 골랐어요');
          final showRetry =
              fb == null && widget.onDisableHighwayAndRetry != null;
          final linkFg =
              isDark ? AppColors.darkBlueBright : const Color(0xFF2563EB);
          return _noteRow(
            isDark,
            label: '경로 유형',
            text: msg,
            // 액션은 안내 문장 아래 오른쪽에 글자 버튼으로만 — 박스를 되살리지 않는다.
            trailing: showRetry
                ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onDisableHighwayAndRetry,
                      icon: Icon(Icons.refresh_rounded, size: 15, color: linkFg),
                      label: Text('필터 끄고 재조회',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: linkFg)),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  )
                : null,
          );
        }),
    ];

    final sheetChildren = <Widget>[
      // ── 기준 카드 (4a) — 잔량·유종·범위를 한 덩어리로 ──
      // 유종 칩과 '연료 범위' 줄이 추천과 잔량 편집 사이에 끼어 보이던 문제를
      // 이 카드가 흡수한다 (충전과 동일 구조, 색만 파랑. 형 제보 2026-08-20).
      if (widget.levelPercent != null)
        LevelBasisCard(
            levelPercent: widget.levelPercent!,
            kmPerPercent: widget.kmPerPercent ?? 0,
            isEv: false,
            onEdit: widget.onEditLevel,
            // 유종만 남긴다 — 어느 유종 가격 기준인지는 실제 정보다.
            // '도달 범위 내'는 항상 참이라 뺐다(위 '주행 가능 약 N km'와 중복).
            conditionLabel: widget.fuelLabel,
            notes: basisNotes)
      else ...[
        // 기준 카드가 없는 경로 — 기존 유종 칩 + 범위 안내 줄 유지
        if (widget.fuelLabel != null) ...[
          _FuelChip(label: widget.fuelLabel!),
          const SizedBox(height: 10),
        ],
        if (reachable != null && reachable['enabled'] == true) ...[
          _noteRow(isDark,
              label: '연료 범위',
              text: '지금 연료로 도달 가능한 범위 안에서만 추천했어요'),
          const SizedBox(height: 10),
        ],
        for (final n in basisNotes) ...[n, const SizedBox(height: 10)],
      ],

      if (uiMessage.isNotEmpty) ...[
        _AiMessageBanner(
          message: uiMessage,
          // 앞말은 작게(어디와 비교했는지), 본문은 크게(핵심 숫자·결론).
          regularLabel: regIsPrimary
              ? (regSecondAlsoMine ? '1·2순위 모두 단골이에요 — ' : '오늘은 ')
              : (regDiffWon != null ? '단골 ${regName ?? '주유소'}보다 ' : null),
          regularLine: regIsPrimary
              ? '단골이 최적이에요'
              : (regDiffWon != null
                  ? '약 ${_wonFmt.format(regDiffWon)}원 이득'
                  : null),
        ),
        const SizedBox(height: 12),
      ],

      // ── 비교 테이블 (AI 추천 원본) / 카드 (사용자 대안 선택 시) ──
      if (!hasOverride && !noStationToRecommend) ...[
        _StationComparisonSection(
          onRouteName: _stationNameFrom(onRouteSt),
          onRoutePrice: orPrice,
          onRouteCost: orCost,
          onRouteDetourM: orDetourM,
          onRouteDetourTimeMin: orDetourTimeMin,
          onRouteLat: orLat,
          onRouteLng: orLng,
          onRouteFuelType: onRouteSt?['fuel_type']?.toString(),
          onRouteBrand: onRouteSt?['brand']?.toString(),
          onRouteStationId: onRouteSt?['id']?.toString(),
          showDetour: showDetour,
          detourName: showDetour ? _stationNameFrom(detourSt) : '',
          detourBrand: detourSt?['brand']?.toString(),
          detourStationId: detourSt?['id']?.toString(),
          regularDiffWon: regDiffWon,
          regularIsPrimary: regIsPrimary,
          regularName: regName,
          regularSecondAlsoMine: regSecondAlsoMine,
          detourPrice: dtPrice,
          detourCost: dtCost,
          dtDetourM: dtDetourM,
          dtDetourTimeMin: dtDetourTimeMin,
          dtLat: dtLat,
          dtLng: dtLng,
          detourFuelType: detourSt?['fuel_type']?.toString(),
          aiRecIsDetour: aiRecIsDetour,
          isDualDetour: isDualDetour,
          isOnRouteVirtual: isOnRouteVirtual,
          rankedMode: isRankedMode,
          dtSavings: dtSavings,
          dtDetourMins: dtTimeMinsBanner,
          fuelLabel: widget.fuelLabel,
          destLat: destLat,
          destLng: destLng,
          destinationName: widget.destinationName,
          originLat: widget.originLat,
          originLng: widget.originLng,
          wonFmt: _wonFmt,
          onViewOnMapRoute: onRoute != null && widget.onAltRouteView != null
              ? () => widget.onAltRouteView!(onRoute)
              : null,
          onViewOnMapDetour: bestDetour != null && widget.onAltRouteView != null
              ? () => widget.onAltRouteView!(bestDetour)
              : null,
        ),
        const SizedBox(height: 12),
      ] else if (!hasOverride && noStationToRecommend) ...[
        // 주유 불필요 케이스 — AI 경로 추천 배너(ui_message)가 이미 설명하므로
        // 같은 말을 반복하는 노란 배너는 안 그린다(형 제보 2026-08-20).
        // 서버 메시지가 비어 있을 때만 폴백으로 노출.
        if (uiMessage.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkAmberBright.withValues(alpha: 0.14)
                : const Color(0xFFFFF9E8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark
                    ? AppColors.darkAmberBright.withValues(alpha: 0.35)
                    : const Color(0xFFFFE6A6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18,
                  color: isDark
                      ? AppColors.darkAmberBright
                      : const Color(0xFF8A6D3B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '현재 연료로 목적지 도달이 가능해 지금은 추천 주유소를 표시하지 않습니다.',
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkAmberBright
                          : const Color(0xFF8A6D3B),
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ] else ...[
        _buildCard(primary, destLat, destLng),
        const SizedBox(height: 10),
        if (secondary != null) ...[
          const SizedBox(height: 2),
          _gasCompare(secondary, primary),
          const SizedBox(height: 12),
        ],
      ],

      // ── 상세 비교표 (팝업) ──
      if (!noStationToRecommend) ...[
        GestureDetector(
          onTap: _showComparisonDetailSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : const Color(0xFFF3F5F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_chart_rounded,
                    size: 16,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('상세 비교표 보기',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF475569))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // ── 다른 후보 ──
      if (data['alternatives'] is List &&
          (data['alternatives'] as List).isNotEmpty) ...[
        _AltSection(
          alternatives: data['alternatives'] as List<dynamic>,
          wonFmt: _wonFmt,
          onSelect: _selectAlt,
          selectedItem: _selectedAltItem,
        ),
        const SizedBox(height: 12),
      ],

      // ── 기준 정보 ──
      if (goalL != null)
        Center(
          child: Text(
            '목표 주유량 약 ${goalL.toStringAsFixed(1)}L 기준',
            style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
          ),
        ),
    ];

    if (widget.scrollController != null) {
      return CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedSheetHandleDelegate(),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver:
                SliverList(delegate: SliverChildListDelegate(sheetChildren)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: sheetChildren,
    );
  }

  Widget _buildCard(_CardInfo c, double? destLat, double? destLng) {
    final canRestoreAiRec = _selectedAltItem != null && c.tag == 'AI 추천';
    final extraInfo = (c.savings > 0 && !c.isUserSelected)
        ? _ExtraInfo(
            savings: c.savings,
            timeMins: _meaningfulDetourMinutes(c.detourTimeMin))
        : null;
    // 지도에서 보기: rawData가 있을 때 onAltRouteView 재사용
    final onViewOnMap = (c.rawData != null && widget.onAltRouteView != null)
        ? () => widget.onAltRouteView!(c.rawData!)
        : null;
    return _OptionCard(
      tag: c.tag,
      tagColor: c.tagColor,
      isAiRec: c.isAiRec,
      isUserSelected: c.isUserSelected,
      stationId: c.stationId,
      stationBrand: c.brandCode,
      stName: c.name,
      stAddr: c.addr,
      priceL: c.price,
      expectedCost: c.cost,
      detourM: c.detourM,
      detourTimeMin: c.detourTimeMin,
      extraInfo: extraInfo,
      stLat: c.lat,
      stLng: c.lng,
      destLat: destLat,
      destLng: destLng,
      destinationName: widget.destinationName,
      originLat: widget.originLat,
      originLng: widget.originLng,
      wonFmt: _wonFmt,
      onViewOnMap: onViewOnMap,
      onRestoreAiRec: canRestoreAiRec
          ? () {
              setState(() {
                _selectedAltItem = null;
                _altAiMessage = null;
              });
              widget.onResetToAiRec?.call();
            }
          : null,
    );
  }

  String _detourShort(_CardInfo c) {
    if (_detourIsNegligible(
        detourM: c.detourM, detourTimeMin: c.detourTimeMin)) {
      return '우회 없음';
    }
    final m = _meaningfulDetourMinutes(c.detourTimeMin);
    if (m != null && m > 0) return '+${fmtMin(m)}';
    if (c.detourM >= 1000) return '+${(c.detourM / 1000).toStringAsFixed(1)}km';
    if (c.detourM > 0) return '+${c.detourM}m';
    return '우회';
  }

  // 두 후보(경로상 최저가 vs 우회 추천)를 나란히 — 한눈 비교. 추천(isAiRec) 쪽 강조.
  Widget _gasCompare(_CardInfo left, _CardInfo right) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, size: 16, color: labelColor),
            const SizedBox(width: 5),
            Text('주유소 비교',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: labelColor)),
            const Spacer(),
            Text('1순위 vs 2순위',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: labelColor)),
          ],
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _compareCol(left, isDark)),
              const SizedBox(width: 10),
              Expanded(child: _compareCol(right, isDark)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compareCol(_CardInfo c, bool isDark) {
    final isRec = c.isAiRec;
    final accent = c.tagColor;
    final bg = isRec
        ? (isDark
            ? accent.withValues(alpha: 0.16)
            : accent.withValues(alpha: 0.06))
        : (isDark ? AppColors.darkCard : Colors.white);
    final borderC = isRec
        ? accent
        : (isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0));
    final nameColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final mutedColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    final onTap = (c.rawData != null && widget.onAltRouteView != null)
        ? () => widget.onAltRouteView!(c.rawData!)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: borderC, width: isRec ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isRec
                    ? accent
                    : (isDark
                        ? const Color(0x22FFFFFF)
                        : const Color(0xFFEEF2F6)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(c.tag,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isRec ? Colors.white : mutedColor)),
            ),
            const SizedBox(height: 8),
            Text(c.name,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: nameColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: c.price != null
                        ? _wonFmt.format(c.price!.round())
                        : '—',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: nameColor)),
                TextSpan(
                    text: ' 원/L',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: mutedColor)),
              ]),
            ),
            const SizedBox(height: 3),
            Text('예상 ${_wonFmt.format(c.cost)}원',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: mutedColor)),
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(Icons.alt_route_rounded, size: 13, color: mutedColor),
                const SizedBox(width: 3),
                Text(_detourShort(c),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: nameColor)),
              ],
            ),
            if (c.savings > 0) ...[
              const SizedBox(height: 4),
              Text('${_wonFmt.format(c.savings)}원 절약 ↓',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A))),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 카드 데이터 헬퍼 ──────────────────────────────────────────────────────────

class _CardInfo {
  final String name;
  final String? addr;
  final double? lat, lng, price;
  final int cost, detourM, savings;
  final num? detourTimeMin;
  final String tag;
  final Color tagColor;
  final bool isAiRec;
  final bool isUserSelected;
  final Map<String, dynamic>? rawData; // on_route / best_detour 원본 (지도 재드로우용)
  final String? stationId; // 단골 등록 유도 카운트용
  final String? brandCode;

  const _CardInfo({
    required this.name,
    required this.addr,
    required this.lat,
    required this.lng,
    required this.price,
    required this.cost,
    required this.detourM,
    required this.detourTimeMin,
    required this.savings,
    required this.tag,
    required this.tagColor,
    required this.isAiRec,
    required this.isUserSelected,
    this.rawData,
    this.stationId,
    this.brandCode,
  });
}

class _ExtraInfo {
  final int savings;
  final int? timeMins;
  const _ExtraInfo({required this.savings, required this.timeMins});
}

// 사용자 표시용 '연료 기준 절약'(시간값 제외) — 전 카드/후보 통일. 서버 fuel_savings_won 우선.
// (시간당 손해 계산은 내부 추천 로직일 뿐, 사용자에겐 연료 기준 금액만 보여줘야 안 헷갈림)
int _fuelSavingsWon(Map item) {
  int p(dynamic v) => v is num ? v.round() : (int.tryParse('${v ?? 0}') ?? 0);
  if (item['fuel_savings_won'] is num) return p(item['fuel_savings_won']);
  if (item['real_savings_won'] is num)
    return p(item['real_savings_won']); // 구서버 폴백
  if (item['savings_vs_primary_won'] is num)
    return p(item['savings_vs_primary_won']);
  return p(item['savings_vs_on_route_won']);
}

String _fuelCodeToLabel(String? code) {
  switch (code) {
    case 'B027':
      return '휘발유';
    case 'B034':
      return '고급휘발유';
    case 'D047':
      return '경유';
    case 'K015':
      return 'LPG';
    case 'C004':
      return '등유';
    default:
      return '';
  }
}

String _resolveFuelLabel(dynamic rawFuel, {String? fallback}) {
  final value = rawFuel?.toString().trim();
  if (value == null || value.isEmpty) return fallback ?? '—';
  final mapped = _fuelCodeToLabel(value);
  return mapped.isNotEmpty ? mapped : value;
}

String _stationNameFrom(dynamic station) {
  if (station is! Map) return '';
  final dn = station['display_name']?.toString().trim();
  final original =
      (dn != null && dn.isNotEmpty) ? dn : (station['name']?.toString() ?? '');
  // 사용자 별칭 우선 적용 — gas AI 추천 결과 카드에도 별칭 노출.
  final id = (station['id'] ?? '').toString();
  if (id.isEmpty) return original;
  return StationAliasService.resolveGas(id, original);
}

// ─── 유종 칩 ──────────────────────────────────────────────────────────────────

class _FuelChip extends StatelessWidget {
  final String label;
  const _FuelChip({required this.label});

  static const _fuelColors = <String, Color>{
    '휘발유': Color(0xFF1D9E75),
    '고급휘발유': Color(0xFF7B61FF),
    '경유': Color(0xFF1D6FE0),
    'LPG': Color(0xFFE07B1D),
  };

  static const _fuelIcons = <String, IconData>{
    '휘발유': Icons.local_gas_station_rounded,
    '고급휘발유': Icons.local_gas_station_rounded,
    '경유': Icons.local_gas_station_rounded,
    'LPG': Icons.propane_tank_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _fuelColors[label] ?? _kPrimary;
    final icon = _fuelIcons[label] ?? Icons.local_gas_station_rounded;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '기준 분석',
          style: TextStyle(
              fontSize: 11,
              color:
                  isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
        ),
      ],
    );
  }
}

// ─── AI 메시지 배너 ────────────────────────────────────────────────────────────

class _AiMessageBanner extends StatelessWidget {
  final String message;

  /// 단골 대비 강조 문구 — 서버 ui_message(제미나이 문구)에는 단골 개념이 없어서
  /// 앱이 배너 본문 아래에 덧붙인다. 조건 미충족이면 null → 줄 자체 없음.
  /// regularLabel(작은 앞말) + regularLine(굵은 본문) 두 단으로 강조한다.
  final String? regularLine;
  final String? regularLabel;

  const _AiMessageBanner(
      {required this.message, this.regularLine, this.regularLabel});

  @override
  Widget build(BuildContext context) {
    final normalized =
        _normalizeMarkdownForKorean(message.replaceAll(r'\n', '\n'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 다크: 파랑 틴트 공식 (accent 14% bg + 35% border + 밝은 파랑 텍스트)
    final blue = isDark ? AppColors.darkBlueBright : const Color(0xFF1D6FE0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // 주유 AI 경로추천 배너 — 파랑 톤 (추천카드 주황과 구분).
        color: isDark
            ? AppColors.darkBlueBright.withValues(alpha: 0.12)
            : const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? AppColors.darkBlueBright.withValues(alpha: 0.35)
                : const Color(0xFFD6E4FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkBlueBright.withValues(alpha: 0.18)
                  : const Color(0xFFE3EEFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 12, color: blue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 경로 추천',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: blue)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF1a1a1a)),
                    strong: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkBlueBright : _kPrimary,
                    ),
                  ),
                ),
                if (regularLine != null) ...[
                  const SizedBox(height: 10),
                  // 아이콘·이모지 없이 — 배너 안에서 한 단 내려 구분선으로 나누고
                  // 금액만 크게 강조한다(형 지적: 아이콘 붙이면 AI 스럽고 산만하다).
                  Container(
                    height: 1,
                    color: blue.withValues(alpha: isDark ? 0.22 : 0.16),
                  ),
                  const SizedBox(height: 9),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: regularLabel ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF5A6B85)),
                        ),
                        TextSpan(
                          text: regularLine!,
                          style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: blue),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 주유소 비교 테이블 섹션 ──────────────────────────────────────────────────────

class _StationComparisonSection extends StatelessWidget {
  final String onRouteName;
  final double? onRoutePrice;
  final int onRouteCost;
  final int onRouteDetourM;
  final num? onRouteDetourTimeMin;
  final double? onRouteLat;
  final double? onRouteLng;
  final String? onRouteFuelType;

  final String? onRouteBrand;
  final String? onRouteStationId;
  final bool showDetour;
  final String detourName;
  final String? detourBrand;
  final String? detourStationId;

  /// 단골 대비 표시 가능 차액 (matched && !is_primary && diff>0 일 때만 non-null)
  final int? regularDiffWon;

  /// 단골이 이번 추천 1순위 자체인지 — '단골' 배지 + 최적 문구
  final bool regularIsPrimary;

  /// 서버가 비교에 쓴 단골(station_id)의 로컬 이름 — 문구용, 없으면 폴백
  final String? regularName;

  /// 1·2순위가 모두 내 단골인 경우.
  final bool regularSecondAlsoMine;
  final double? detourPrice;
  final int detourCost;
  final int dtDetourM;
  final num? dtDetourTimeMin;
  final double? dtLat;
  final double? dtLng;
  final String? detourFuelType;

  final bool aiRecIsDetour;
  final bool isDualDetour;
  final bool isOnRouteVirtual;
  final bool rankedMode; // 통합 랭킹 프레임 — 태그를 추천/차선으로
  final int dtSavings;
  final int? dtDetourMins;
  final String? fuelLabel;

  final double? destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMapRoute;
  final VoidCallback? onViewOnMapDetour;

  const _StationComparisonSection({
    required this.onRouteName,
    required this.onRoutePrice,
    required this.onRouteCost,
    required this.onRouteDetourM,
    required this.onRouteDetourTimeMin,
    required this.onRouteLat,
    required this.onRouteLng,
    required this.onRouteFuelType,
    this.onRouteBrand,
    this.onRouteStationId,
    required this.showDetour,
    required this.detourName,
    this.detourBrand,
    this.detourStationId,
    this.regularDiffWon,
    this.regularIsPrimary = false,
    this.regularName,
    this.regularSecondAlsoMine = false,
    required this.detourPrice,
    required this.detourCost,
    required this.dtDetourM,
    required this.dtDetourTimeMin,
    required this.dtLat,
    required this.dtLng,
    required this.detourFuelType,
    required this.aiRecIsDetour,
    required this.isDualDetour,
    required this.isOnRouteVirtual,
    this.rankedMode = false,
    required this.dtSavings,
    required this.dtDetourMins,
    required this.fuelLabel,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMapRoute,
    this.onViewOnMapDetour,
  });

  String _detourLabel(int detourM, num? detourTimeMin) {
    if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin))
      return '우회 없음';
    final m = _meaningfulDetourMinutes(detourTimeMin);
    if (m != null && m > 0) return '+${m}분';
    if (detourM >= 1000) return '+${(detourM / 1000).toStringAsFixed(1)}km';
    if (detourM > 0) return '+${detourM}m';
    return '조금 우회';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasOnRoute = onRouteName.trim().isNotEmpty;
    final bool hasBoth = hasOnRoute && showDetour && detourName.isNotEmpty;
    // 서버가 한쪽만 내려줘도 표는 그림(빈 열은 —)
    final bool showComparisonTable =
        hasOnRoute || (showDetour && detourName.trim().isNotEmpty);

    // 추천 주유소 결정
    // on_route가 없으면 detour(우회 최저가)를 추천 카드로 강제
    final recIsDetour = (!hasOnRoute && showDetour && detourName.isNotEmpty) ||
        (aiRecIsDetour && hasBoth);
    final recName = recIsDetour ? detourName : onRouteName;
    final recBrand = recIsDetour ? detourBrand : onRouteBrand;
    final recStationId = recIsDetour ? detourStationId : onRouteStationId;
    final recPrice = recIsDetour ? detourPrice : onRoutePrice;
    final recCost = recIsDetour ? detourCost : onRouteCost;
    final recDetourM = recIsDetour ? dtDetourM : onRouteDetourM;
    final recDetourTimeMin =
        recIsDetour ? dtDetourTimeMin : onRouteDetourTimeMin;
    final recLat = recIsDetour ? dtLat : onRouteLat;
    final recLng = recIsDetour ? dtLng : onRouteLng;
    final onViewRec = recIsDetour ? onViewOnMapDetour : onViewOnMapRoute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 추천 카드 ──
        _RecommendedCard(
          name: recName,
          brand: recBrand,
          stationId: recStationId,
          regularDiffWon: regularDiffWon,
          regularIsPrimary: regularIsPrimary,
          regularName: regularName,
          regularSecondAlsoMine: regularSecondAlsoMine,
          price: recPrice,
          cost: recCost,
          detourM: recDetourM,
          detourTimeMin: recDetourTimeMin,
          stLat: recLat,
          stLng: recLng,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          originLat: originLat,
          originLng: originLng,
          isDetour: recIsDetour,
          wonFmt: wonFmt,
          onViewOnMap: onViewRec,
        ),

        // ── 비교 테이블 (한쪽만 있어도 추천 정보 표 형태로 표시) ──
        if (showComparisonTable) ...[
          const SizedBox(height: 12),
          _CompareCards(
            onRouteName: onRouteName,
            onRoutePrice: onRoutePrice,
            onRouteCost: onRouteCost,
            onRouteDetourLabel:
                _detourLabel(onRouteDetourM, onRouteDetourTimeMin),
            onRouteFuelLabel:
                _resolveFuelLabel(onRouteFuelType, fallback: fuelLabel),
            onRouteStationId: onRouteStationId,
            onRouteBrand: onRouteBrand,
            detourName: detourName,
            detourPrice: detourPrice,
            detourCost: detourCost,
            detourStationId: detourStationId,
            detourBrand: detourBrand,
            detourDetourLabel: _detourLabel(dtDetourM, dtDetourTimeMin),
            detourFuelLabel:
                _resolveFuelLabel(detourFuelType, fallback: fuelLabel),
            savings: dtSavings,
            detourMins: dtDetourMins,
            aiRecIsDetour: aiRecIsDetour,
            isDualDetour: isDualDetour,
            isOnRouteVirtual: isOnRouteVirtual,
            // 통합 랭킹 — 경로상/우회 대신 추천/차선 (라벨-실측 역전 혼란 해소)
            tagLeft: rankedMode ? '추천' : null,
            tagRight: rankedMode ? '차선' : null,
            fuelLabel: fuelLabel,
            wonFmt: wonFmt,
            onViewOnMapRoute: onViewOnMapRoute,
            onViewOnMapDetour: onViewOnMapDetour,
            onRouteLat: onRouteLat,
            onRouteLng: onRouteLng,
            dtLat: dtLat,
            dtLng: dtLng,
            destLat: destLat,
            destLng: destLng,
            destinationName: destinationName,
            originLat: originLat,
            originLng: originLng,
          ),
        ],
      ],
    );
  }
}

// ── 추천 주유소 카드 ──────────────────────────────────────────────────────────

/// AI 추천 카드 (형 시안 6a) — 배지 + 이름 + 수치 타일 + CTA, 파랑 단일 축.
/// 절약 문구는 위 AI 배너가 담당하므로 카드는 사실만 담백하게. 블링은 추천 배지에.
class _RecommendedCard extends StatelessWidget {
  final String name;
  final String? brand;
  final String? stationId; // 단골 등록 유도 카운트용 (경유 길안내 실행 시)
  final double? price;
  final int cost;
  final int detourM;
  final num? detourTimeMin;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final bool isDetour;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;

  /// 단골 대비 이득 한 줄 (>0 일 때만 non-null — 조건 미충족이면 줄 자체 없음)
  final int? regularDiffWon;

  /// 단골이 1순위 자체 — '단골' 배지 + "오늘은 단골이 최적이에요"
  final bool regularIsPrimary;

  /// 비교에 쓰인 단골의 이름 (regular_compare.station_id → 로컬 목록)
  final String? regularName;

  /// 1·2순위가 모두 내 단골인 경우.
  final bool regularSecondAlsoMine;

  const _RecommendedCard({
    required this.name,
    this.brand,
    this.stationId,
    this.regularDiffWon,
    this.regularIsPrimary = false,
    this.regularName,
    this.regularSecondAlsoMine = false,
    required this.price,
    required this.cost,
    required this.detourM,
    required this.detourTimeMin,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.isDetour,
    required this.wonFmt,
    this.onViewOnMap,
  });

  /// "단골 ○○보다 약 N원 이득" — 다른 기기 동기화 등으로 로컬에 이름이 없으면
  /// '단골 주유소' 로 폴백 (긴 이름은 Row 의 Expanded + ellipsis 가 처리).
  /// 케이스별 단골 문구 — 조건 미충족이면 null 이라 줄 자체가 없다.
  ///  · 1순위가 단골 (+2순위도 단골이면 두 곳 다 안내)
  ///  · 단골보다 추천이 이득
  /// 단골이 오히려 더 저렴한 경우(고속도로 모드는 1위를 경로상으로 고정, 브랜드
  /// 필터는 단골을 랭킹 풀에서 제외)는 **일부러 아무 말도 하지 않는다** — 추천
  /// 바로 밑에서 "님 단골이 더 싸요"는 자기모순으로 읽힌다(형 결정 2026-08-18).
  String? _regularLine() {
    final rn = (regularName ?? '').trim();
    final target = rn.isEmpty ? '단골 주유소' : '단골 $rn';
    if (regularIsPrimary) {
      return regularSecondAlsoMine
          ? '1·2순위 모두 단골이에요'
          : '오늘은 단골이 최적이에요';
    }
    if (regularDiffWon != null && regularDiffWon! > 0) {
      return '$target보다 약 ${wonFmt.format(regularDiffWon)}원 이득';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = _kMarkerRecommend;
    final canNav =
        stLat != null && stLng != null && destLat != null && destLng != null;
    final isNegligible =
        _detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin);
    final detourMins = _meaningfulDetourMinutes(detourTimeMin);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final primary =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final chipBg = isDark ? const Color(0x1FFFFFFF) : Colors.white;
    final chipBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFD6E4F7);
    final tileBg = isDark ? AppColors.darkSurface2 : const Color(0xFFF6F8FB);

    Widget tile(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                FittedBox(
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: primary)),
                ),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted)),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14202F) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark
                ? AppColors.darkBlueBright.withValues(alpha: 0.55)
                : accent.withValues(alpha: 0.45),
            width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 배지 행: [추천(블링)] [경로상/우회 최저가] ─ [지도] ──
          Row(
            children: [
              _ShimmerSweep(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: accent, borderRadius: BorderRadius.circular(6)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 11, color: Colors.white),
                      SizedBox(width: 4),
                      Text('추천',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: chipBorder),
                ),
                child: Text(isDetour ? '우회 최저가' : '경로상 최저가',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : const Color(0xFF44546A))),
              ),
              // 단골 = 1순위 — 차액 비교 대신 배지로 (설계서 §3)
              if (regularIsPrimary) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: (isDark ? AppColors.darkBlueBright : accent)
                            .withValues(alpha: 0.45)),
                  ),
                  child: Text('단골',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? AppColors.darkBlueBright : accent)),
                ),
              ],
              const Spacer(),
              if (onViewOnMap != null)
                GestureDetector(
                  onTap: onViewOnMap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: chipBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 13,
                            color: isDark
                                ? AppColors.darkBlueBright
                                : accent),
                        const SizedBox(width: 3),
                        Text('지도',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkBlueBright
                                    : accent)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 11),
          // ── 브랜드 + 이름 ──
          Row(
            children: [
              if (brand != null && brand!.isNotEmpty) ...[
                BrandLogo(brand: brand!, stationName: name),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 수치 타일 3개 ──
          Row(
            children: [
              tile(price != null ? '${wonFmt.format(price!.round())}원' : '—',
                  '리터당'),
              const SizedBox(width: 8),
              tile(
                  isNegligible
                      ? '우회 없음'
                      : (detourMins != null ? '+$detourMins분' : '조금 우회'),
                  '직행 대비'),
              const SizedBox(width: 8),
              tile(cost > 0 ? '${wonFmt.format(cost)}원' : '—', '예상 주유비'),
            ],
          ),
          // ── 단골 비교 한 줄 (보조 정보 톤 — 조건 미충족이면 줄 자체 없음) ──
          if (_regularLine() != null) ...[
            const SizedBox(height: 10),
            // 아이콘 없이 — 카드 안에서는 배경 띠로 구분하고 금액만 굵게(형 지적:
            // 아이콘을 앞에 붙이면 AI 스럽다). 긴 주유소명은 ellipsis.
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                _regularLine()!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: isDark ? AppColors.darkBlueBright : accent),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // ── 길안내 CTA ──
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: canNav
                  ? () async {
                      await showViaWaypointNavigationSheet(
                        context,
                        originLat: originLat,
                        originLng: originLng,
                        waypointLat: stLat!,
                        waypointLng: stLng!,
                        waypointName: name,
                        destinationLat: destLat!,
                        destinationLng: destLng!,
                        destinationName: destinationName,
                        stopKind: '주유소',
                      );
                      // 단골 등록 유도 — 같은 곳 3회째에 1회만 (서비스가 판단)
                      if (context.mounted &&
                          stationId != null &&
                          stationId!.isNotEmpty) {
                        RegularStationService.onGasNavigated(context,
                            id: stationId!, name: name, brand: brand);
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.route_rounded, size: 16),
              label: const Text('경유 길안내',
                  style:
                      TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 블링블링 — 자식 위를 밝은 띠가 주기적으로 쓸고 지나가는 shimmer (형 요청 ㅋㅋ).
/// srcATop 이라 자식이 그려진 픽셀 위에만 얹힌다(배경 오염 없음).
class _ShimmerSweep extends StatefulWidget {
  const _ShimmerSweep({required this.child});

  final Widget child;

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // 앞 60% 동안 왼→오로 쓸고, 나머지 40% 은 쉼 — 계속 번쩍이면 정신없다.
        final t = (_c.value / 0.6).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) {
            final x = (t * 2 - 0.5) * r.width;
            return LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromLTWH(x, 0, r.width * 0.55, r.height));
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RecStatCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  /// true 면 다크모드에서 밝은 글자 — 다크 대응 카드(직접선택 추천카드)용.
  /// AI 히어로 카드는 다크에서도 흰 박스 고정이라 false(진한 글자) 유지.
  final bool darkAdaptive;

  const _RecStatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.darkAdaptive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 7),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: darkAdaptive && isDark
                      ? AppColors.darkTextPrimary
                      : const Color(0xFF1a1a1a))),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : const Color(0xFF999999))),
        ],
      ),
    );
  }
}

// ── 비교 테이블 ──────────────────────────────────────────────────────────────

// 경로상 최저가 vs 우회 최저가 — 반응형 2-up 카드(둘 다 지도+경로안내). 표 대체.
class _CompareCards extends StatelessWidget {
  final String onRouteName;
  final double? onRoutePrice;
  final int onRouteCost;
  final String onRouteDetourLabel;
  final String onRouteFuelLabel;
  final String? onRouteStationId; // 단골 유도 카운트용
  final String? onRouteBrand;
  final String detourName;
  final double? detourPrice;
  final int detourCost;
  final String? detourStationId;
  final String? detourBrand;
  final String detourDetourLabel;
  final String detourFuelLabel;
  final int savings;
  final int? detourMins;
  final bool aiRecIsDetour;
  final bool isDualDetour;
  final bool isOnRouteVirtual;
  // A/B 직접선택 비교 재사용 시 기본 라벨('경로상/우회 최저가') 대체
  final String? tagLeft, tagRight;
  final String? fuelLabel;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMapRoute;
  final VoidCallback? onViewOnMapDetour;
  final double? onRouteLat, onRouteLng, dtLat, dtLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;

  const _CompareCards({
    required this.onRouteName,
    required this.onRoutePrice,
    required this.onRouteCost,
    required this.onRouteDetourLabel,
    required this.onRouteFuelLabel,
    this.onRouteStationId,
    this.onRouteBrand,
    required this.detourName,
    required this.detourPrice,
    required this.detourCost,
    this.detourStationId,
    this.detourBrand,
    required this.detourDetourLabel,
    required this.detourFuelLabel,
    required this.savings,
    required this.detourMins,
    required this.aiRecIsDetour,
    this.isDualDetour = false,
    this.isOnRouteVirtual = false,
    this.tagLeft,
    this.tagRight,
    required this.fuelLabel,
    required this.wonFmt,
    this.onViewOnMapRoute,
    this.onViewOnMapDetour,
    required this.onRouteLat,
    required this.onRouteLng,
    required this.dtLat,
    required this.dtLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
  });

  static const _amber = Color(0xFF3B82F6); // (이름은 유산 — 현재 1순위 강조 파랑)
  static const _green = Color(0xFF2563EB); // 절약 표기도 파랑 축

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOnRoute = onRouteName.trim().isNotEmpty;
    final hasDetour = detourName.trim().isNotEmpty;
    final detourIsWinner = aiRecIsDetour;
    final labelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);

    VoidCallback? navTo(
        double? lat, double? lng, String name, String? id, String? brand) {
      if (lat == null || lng == null || destLat == null || destLng == null) {
        return null;
      }
      return () async {
        await showViaWaypointNavigationSheet(
          context,
          originLat: originLat,
          originLng: originLng,
          waypointLat: lat,
          waypointLng: lng,
          waypointName: name,
          destinationLat: destLat!,
          destinationLng: destLng!,
          destinationName: destinationName,
          stopKind: '주유소',
        );
        // 단골 등록 유도 — 같은 곳 3회째에 1회만 (서비스가 판단)
        if (context.mounted && id != null && id.isNotEmpty) {
          RegularStationService.onGasNavigated(context,
              id: id, name: name, brand: brand);
        }
      };
    }

    final cols = <Widget>[];
    if (hasOnRoute) {
      cols.add(_col(
        isDark: isDark,
        tag: tagLeft ?? (isOnRouteVirtual ? '근거리 우회' : '경로상 최저가'),
        isWinner: !detourIsWinner,
        name: onRouteName,
        price: onRoutePrice,
        cost: onRouteCost,
        detourLabel: onRouteDetourLabel,
        savingsText: null,
        onMap: onViewOnMapRoute,
        onNav: navTo(
            onRouteLat, onRouteLng, onRouteName, onRouteStationId, onRouteBrand),
      ));
    }
    if (hasDetour) {
      cols.add(_col(
        isDark: isDark,
        tag: tagRight ?? '우회 최저가',
        isWinner: detourIsWinner,
        name: detourName,
        price: detourPrice,
        cost: detourCost,
        detourLabel: detourDetourLabel,
        savingsText: savings > 0 ? '${wonFmt.format(savings)}원 ↓' : null,
        onMap: onViewOnMapDetour,
        onNav: navTo(dtLat, dtLng, detourName, detourStationId, detourBrand),
      ));
    }
    if (cols.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, size: 16, color: labelColor),
            const SizedBox(width: 5),
            Text('주유소 비교',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: labelColor)),
            if (fuelLabel != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x22FFFFFF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(fuelLabel!,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: labelColor)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 9),
        // ★ 두 경우 모두 IntrinsicHeight 로 감싼다 — 카드 내부 Column 이 하단 버튼을
        //   Spacer 로 밀어 붙이는데(_col), Spacer 는 높이가 유한해야 성립한다.
        //   시트는 스크롤 안이라 높이가 무한이므로, 카드 1장만 그릴 때(우회 후보가
        //   없어 추천이 1곳뿐인 응답) 감싸지 않으면 레이아웃 단계에서 예외가 나고
        //   시트 전체가 통째로 안 그려졌다 — "결과가 백지"(형 제보 2026-08-19).
        if (cols.length == 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cols[0]),
                const SizedBox(width: 10),
                Expanded(child: cols[1]),
              ],
            ),
          )
        else
          IntrinsicHeight(child: cols.first),
        const SizedBox(height: 9),
        _banner(isDark, labelColor),
      ],
    );
  }

  Widget _col({
    required bool isDark,
    required String tag,
    required bool isWinner,
    required String name,
    required double? price,
    required int cost,
    required String detourLabel,
    required String? savingsText,
    required VoidCallback? onMap,
    required VoidCallback? onNav,
  }) {
    final bg = isWinner
        ? (isDark ? _amber.withValues(alpha: 0.16) : const Color(0xFFFFFBEB))
        : (isDark ? AppColors.darkCard : Colors.white);
    final borderC = isWinner
        ? _amber
        : (isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0));
    final nameColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final muted =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderC, width: isWinner ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // 카드 높이는 IntrinsicHeight+stretch 로 두 카드가 같아지는데, 내용 줄 수가
        // 다르면(절약문구 유무 등) 버튼 행이 카드마다 다른 높이에서 떠 있었다(형 제보) →
        // min 대신 채우고 버튼 위에 Spacer 로 하단 고정.
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 순위 배지 — 형 시안 6a: 1순위 추천(파랑 채움) / 2순위 차선(회색 칩)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: isWinner
                        ? _amber
                        : (isDark
                            ? const Color(0x22FFFFFF)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(isWinner ? '1순위 추천' : '2순위 차선',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isWinner ? Colors.white : muted)),
              ),
              Text(tag,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isWinner ? _amber : muted)),
            ],
          ),
          const SizedBox(height: 7),
          Text(name,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: nameColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: price != null ? wonFmt.format(price.round()) : '—',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: nameColor)),
                TextSpan(
                    text: ' 원/L',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted)),
              ]),
            ),
          ),
          const SizedBox(height: 3),
          Text('예상 ${wonFmt.format(cost)}원',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 13, color: muted),
              const SizedBox(width: 3),
              Flexible(
                child: Text(detourLabel,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: nameColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (savingsText != null) ...[
            const SizedBox(height: 4),
            Text(savingsText,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: _green),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const Spacer(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _navBtn(Icons.map_outlined, '지도', onMap,
                      filled: false, isDark: isDark)),
              const SizedBox(width: 6),
              Expanded(
                  child: _navBtn(Icons.navigation_rounded, '경로안내', onNav,
                      filled: isWinner, isDark: isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback? onTap,
      {required bool filled, required bool isDark}) {
    final enabled = onTap != null;
    final fg = filled
        ? Colors.white
        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF475569));
    final bg = filled
        ? _amber
        : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9));
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 3),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(bool isDark, Color labelColor) {
    const txt = '표시 금액은 우회 시간·연료 등 부대비용까지 반영한 최종 차액이에요. '
        '초록은 그만큼 절약, 빨강 +는 그만큼 더 들어요.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 13, color: labelColor),
        const SizedBox(width: 5),
        Expanded(
          child: Text(txt,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  height: 1.3)),
        ),
      ],
    );
  }
}

// ─── 옵션 카드 ────────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final bool isAiRec;
  final bool isUserSelected;
  final String? stationId; // 단골 등록 유도 카운트용
  final String? stationBrand;
  final String stName;
  final String? stAddr;
  final double? priceL;
  final int expectedCost;
  final int detourM;
  final num? detourTimeMin;
  final _ExtraInfo? extraInfo;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;
  final VoidCallback? onRestoreAiRec;

  const _OptionCard({
    required this.tag,
    required this.tagColor,
    required this.isAiRec,
    required this.isUserSelected,
    this.stationId,
    this.stationBrand,
    required this.stName,
    required this.stAddr,
    required this.priceL,
    required this.expectedCost,
    required this.detourM,
    required this.detourTimeMin,
    required this.extraInfo,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMap,
    this.onRestoreAiRec,
  });

  @override
  Widget build(BuildContext context) {
    final canNav =
        stLat != null && stLng != null && destLat != null && destLng != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color borderColor;
    final Color bgColor;
    final Color navBtnColor;
    final Color navBtnTextColor;

    if (isUserSelected) {
      // 보라 톤(선택됨) — 다크에서는 보라 16% alpha 로 lift.
      borderColor = _kSelected;
      bgColor = isDark ? _kSelected.withValues(alpha: 0.16) : _kSelectedLight;
      navBtnColor = _kSelected;
      navBtnTextColor = Colors.white;
    } else if (isAiRec) {
      // 초록 톤(AI 추천) — 다크에서는 초록 16% alpha 로 lift.
      borderColor = _kPrimary;
      bgColor = isDark ? _kPrimary.withValues(alpha: 0.16) : _kPrimaryLight;
      navBtnColor = _kPrimary;
      navBtnTextColor = Colors.white;
    } else {
      // 무채색(참고) — 다크에서는 darkCard, 라이트에서는 흰색.
      borderColor = isDark ? AppColors.darkCardBorder : const Color(0xFFDDDDDD);
      bgColor = isDark ? AppColors.darkCard : Colors.white;
      navBtnColor = isDark ? const Color(0x1AFFFFFF) : const Color(0xFFEEEEEE);
      navBtnTextColor =
          isDark ? AppColors.darkTextPrimary : const Color(0xFF444444);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: (isAiRec || isUserSelected) ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tag,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                if (isAiRec) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text('AI 추천',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                if (isUserSelected) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kSelected,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text('내가 선택',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (onRestoreAiRec != null)
                  TextButton.icon(
                    onPressed: onRestoreAiRec,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh_rounded,
                        size: 14, color: _kPrimary),
                    label: const Text(
                      'AI 추천 복원',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kPrimary,
                      ),
                    ),
                  ),
                if (onViewOnMap != null)
                  GestureDetector(
                    onTap: onViewOnMap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x1FFFFFFF)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 13,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF666666)),
                          const SizedBox(width: 3),
                          Text('지도',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : const Color(0xFF666666))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 주유소명 + 주소 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stName,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF1a1a1a))),
                if (stAddr != null && stAddr!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(stAddr!,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : const Color(0xFF888888))),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── 핵심 수치 3종 ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _NumCell(
                    value: priceL != null
                        ? '${wonFmt.format(priceL!.round())}원'
                        : '—',
                    label: '리터당',
                  ),
                  VerticalDivider(
                      width: 1,
                      color: isDark
                          ? AppColors.darkCardBorder
                          : const Color(0xFFDDDDDD)),
                  _DetourStatsCell(
                      detourM: detourM, detourTimeMin: detourTimeMin),
                  VerticalDivider(
                      width: 1,
                      color: isDark
                          ? AppColors.darkCardBorder
                          : const Color(0xFFDDDDDD)),
                  _NumCell(
                    value: expectedCost > 0
                        ? '${wonFmt.format(expectedCost)}원'
                        : '—',
                    label: '예상 주유비',
                    valueSize: 14,
                  ),
                ],
              ),
            ),
          ),

          // ── 절약/시간 정보 (우회 카드) ──
          if (extraInfo != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBlueBright.withValues(alpha: 0.12)
                      : const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.savings_outlined,
                            size: 15,
                            color: isDark
                                ? AppColors.darkBlueBright
                                : const Color(0xFF1D6FE0)),
                        const SizedBox(width: 6),
                        Text(
                          'AI 추천 대비 ${wonFmt.format(extraInfo!.savings)}원 절약',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkBlueBright
                                  : const Color(0xFF1D6FE0)),
                        ),
                      ],
                    ),
                    if (extraInfo!.timeMins != null &&
                        extraInfo!.timeMins! > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 14,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF888888)),
                          const SizedBox(width: 6),
                          Text(
                            '대신 ${extraInfo!.timeMins}분 더 소요',
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : const Color(0xFF666666)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ── 길안내 버튼 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: canNav
                    ? () async {
                        await showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: stName,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                          stopKind: '주유소',
                        );
                        // 단골 등록 유도 — 같은 곳 3회째에 1회만 (서비스가 판단)
                        if (context.mounted &&
                            stationId != null &&
                            stationId!.isNotEmpty) {
                          RegularStationService.onGasNavigated(context,
                              id: stationId!,
                              name: stName,
                              brand: stationBrand);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navBtnColor,
                  foregroundColor: navBtnTextColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 16),
                label: const Text('경유 길안내',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 상세 비교표 (전체 후보 카드 리스트, 가격순) ──────────────────────────────
class _ComparisonDetailSheet extends StatelessWidget {
  final List<Map<String, dynamic>> cards; // 2장: 경로상/우회 (또는 우회/우회)
  final Map<String, dynamic>? cost; // 비용 분해(절약/우회비용/순이득)
  final NumberFormat wonFmt;
  const _ComparisonDetailSheet(
      {required this.cards, required this.cost, required this.wonFmt});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF94A3B8);
    final recColor =
        isDark ? AppColors.darkBlueBright : const Color(0xFF1D6FE0);
    final lineColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEF1F5);
    final c1 = cards[0];
    final c2 = cards.length > 1 ? cards[1] : null;

    Color colColor(Map<String, dynamic> c) =>
        c['isRec'] == true ? recColor : ink;
    String detTxt(Map<String, dynamic> c) {
      final d = (c['detour'] as num?)?.round() ?? 0;
      return d > 0 ? '+$d분' : '우회 없음';
    }

    Widget mRow(String label, String v1, String? v2, {bool big = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            SizedBox(
                width: 76,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: muted,
                        fontWeight: FontWeight.w600))),
            Expanded(
                child: Text(v1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: big ? 14.5 : 13,
                        fontWeight: big ? FontWeight.w800 : FontWeight.w700,
                        color: colColor(c1)))),
            if (c2 != null)
              Expanded(
                  child: Text(v2 ?? '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: big ? 14.5 : 13,
                          fontWeight: big ? FontWeight.w800 : FontWeight.w700,
                          color: colColor(c2)))),
          ]),
        );
    Widget line() => Divider(height: 1, color: lineColor);

    // 색칠 Container 를 SafeArea 밖에 둬야 제스처 내비 기기에서 시트 아래 투명 띠가 안 생기고,
    // 큰 글꼴/소형 폰에서 내용이 화면을 넘으면 스크롤로 흡수한다.
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[isDark ? 700 : 300],
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.compare_arrows_rounded, size: 18, color: recColor),
                const SizedBox(width: 6),
                Text('상세 비교',
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: ink)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                const SizedBox(width: 76),
                Expanded(child: _head(c1, ink, recColor, isDark: isDark)),
                if (c2 != null)
                  Expanded(child: _head(c2, ink, recColor, isDark: isDark)),
              ]),
              const SizedBox(height: 10),
              line(),
              mRow('리터당 가격', _wonNum(c1['price']),
                  c2 != null ? _wonNum(c2['price']) : null,
                  big: true),
              line(),
              mRow('우회 시간', detTxt(c1), c2 != null ? detTxt(c2) : null),
              line(),
              mRow('예상 주유비', _wonNum(c1['cost']),
                  c2 != null ? _wonNum(c2['cost']) : null),
              if (cost != null) ...[
                const SizedBox(height: 14),
                _costVerdictBox(cost!, wonFmt, ink, muted, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 직접선택 경로는 price 가 int(.round()), AI 경로는 double 로 들어와서
  // 캐스트 대신 num 으로 받는다 (int→double 캐스트 크래시 방지).
  String _wonNum(dynamic n) =>
      (n is num && n > 0) ? '${wonFmt.format(n.round())}원' : '-';

  Widget _head(Map<String, dynamic> c, Color ink, Color recColor,
      {required bool isDark}) {
    final isRec = c['isRec'] == true;
    final role = c['role'] as String? ?? '';
    final brand = (c['brand'] as String?) ?? '';
    final roleColor = (role == '경로상' || role == '추천')
        ? (isDark ? AppColors.darkBlueBright : const Color(0xFF2563EB))
        : (isDark ? AppColors.darkBlueBright : const Color(0xFF1D6FE0));
    return Column(children: [
      if (brand.isNotEmpty)
        BrandLogo(brand: brand, stationName: c['name'] as String, size: 30)
      else
        const Icon(Icons.local_gas_station_rounded,
            size: 24, color: Color(0xFF9AA6B2)),
      const SizedBox(height: 5),
      Text(c['name'] as String,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isRec ? recColor : ink,
              height: 1.15)),
      const SizedBox(height: 5),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
              border: Border.all(color: roleColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(5)),
          child: Text(role,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: roleColor)),
        ),
        if (isRec) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
                color: recColor, borderRadius: BorderRadius.circular(5)),
            child: const Text('추천',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ]),
    ]);
  }
}

// 비용 판정 박스 (공용 — AI 상세비교표·직접선택 A/B 비교에서 동일 사용) — 절약 − 우회비용 = 순이득.
Widget _costVerdictBox(Map<String, dynamic> ca, NumberFormat wonFmt, Color ink,
    Color muted, bool isDark) {
  int gi(String k) {
    final v = ca[k];
    if (v is num) return v.round();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  // 원시 가격차(음수=비교대상이 더 비쌈) 우선 — savings_won은 0 클램프라 '+0원' 정보유실.
  final priceDiff =
      ca['price_diff_won'] is num ? gi('price_diff_won') : gi('savings_won');
  final worth = ca['verdict'] == 'detour_worth';
  // 시간값(원)을 돈에 안 섞고 '연료 기준 이득 + 우회 시간(분)'으로 분리 표시.
  final fuelWon = ca['detour_fuel_won'] is num ? gi('detour_fuel_won') : 0;
  final extraMin = ca['detour_extra_min'] is num ? gi('detour_extra_min') : 0;
  // 서버가 시간값(분당 기회비용)까지 총액으로 계산한 경우만 '총비용 한 줄'을 추가로 노출.
  // 순위는 총비용으로 갈리는데 박스엔 연료 기준 절약만 보여서 "돈은 2위가 이득인데 왜
  // 1위냐"가 설명 안 되던 문제(형 제보 — 분당로/구도일 144원 케이스). 시간이 과금 안 된
  // 비교(면제구간 이내·직접선택 합성 ca)는 기존 표시 그대로.
  final int? netWon =
      ca['net_benefit_won'] is num ? (ca['net_benefit_won'] as num).round() : null;
  final int? timeWon =
      ca['detour_time_won'] is num ? (ca['detour_time_won'] as num).round() : null;
  final showTotal = timeWon != null && timeWon > 0 && netWon != null;
  final fuelBenefit = priceDiff - fuelWon; // 연료 기준 순이득(추가연료비까지 뺀 순수 돈)
  // 비교 대상 호칭 — 기본은 우회 후보, 대안 선택 비교면 '선택한 곳'.
  final subject = (ca['subject'] ?? '우회 쪽').toString();
  if (priceDiff == 0 && fuelWon <= 0 && extraMin <= 0) {
    return const SizedBox.shrink();
  }
  // 다크에선 밝은 변형 — 라이트 원색은 어두운 배경에서 대비 미달.
  final green = isDark ? AppColors.darkBlueBright : const Color(0xFF3B82F6);
  // '이득 아님' 판정 — 다크는 이미 파랑이었고 라이트만 주황으로 어긋나 있었다
  // → 중립 슬레이트로 통일 (주황 폐기).
  final orange =
      isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
  final red = isDark ? AppColors.darkRedBright : const Color(0xFFE24B4A);
  final c = worth ? green : orange; // 헤더/판정 색
  final bC = fuelBenefit >= 0 ? green : red; // 이득/손해 색
  final wonF = wonFmt;
  // 판정 문구 — 시간은 분으로만, 이득은 연료 기준. 누굴 추천하는지는 카드 뱃지·AI 메시지가
  // 담당하므로(선택 비교에선 '경로상' 표현이 어긋남) 여긴 판단 근거만 중립적으로.
  String verdict;
  if (priceDiff == 0 && extraMin > 0) {
    // 동가 — 가격 설명이 아니라 시간 차이로 판정 (같은 가격이면 덜 우회하는 쪽)
    verdict = '가격이 같아서, $extraMin분 덜 우회하는 추천 쪽이 이득이에요';
  } else if (extraMin <= 0) {
    verdict =
        fuelBenefit > 0 ? '추가 우회 없이 더 저렴한 곳이에요' : '추가 시간·연료까지 감안하면 이득이 없어요';
  } else if (worth) {
    verdict = '$extraMin분 더 걸려도 ${wonF.format(fuelBenefit)}원 아껴져서 갈 만해요';
  } else if (fuelBenefit > 0) {
    // 총비용(시간값 포함)이 있으면 "왜 그런데도 추천이 안 바뀌는지"를 숫자로 말한다.
    verdict = (netWon != null && netWon < 0)
        ? '${wonF.format(fuelBenefit)}원 아껴지긴 하지만, 시간까지 값으로 치면 총 ${wonF.format(-netWon)}원 손해예요'
        : '${wonF.format(fuelBenefit)}원 아껴지긴 하지만, $extraMin분 더 갈 만큼 차이가 크진 않아요';
  } else {
    verdict = '기름값 차이보다 우회에 드는 기름이 더 커서 이득이 없어요';
  }
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      // 다크: 7% 틴트는 darkCard 와 구분 불가 → 14% + 보더 35%로 존재감 확보
      color: c.withValues(alpha: isDark ? 0.14 : 0.07),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: c.withValues(alpha: isDark ? 0.35 : 0.22)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.calculate_rounded, size: 15, color: c),
        const SizedBox(width: 5),
        Text('우회 이득 판정',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
      ]),
      const SizedBox(height: 8),
      // 부호(+/−) 대신 자연어 — '−273원'이 절약인지 손해인지 해석하게 만들지 않기.
      _costVerdictLine(
          '기름값만 보면',
          priceDiff == 0
              ? '두 곳 가격 같음'
              : (priceDiff > 0
                  ? '$subject이 ${wonF.format(priceDiff)}원 저렴'
                  : '$subject이 ${wonF.format(-priceDiff)}원 비쌈'),
          muted,
          priceDiff > 0 ? green : (priceDiff < 0 ? red : ink)),
      if (fuelWon > 0)
        _costVerdictLine(
            '우회하는 데 드는 기름', '약 ${wonF.format(fuelWon)}원', muted, ink),
      Divider(height: 14, color: c.withValues(alpha: 0.2)),
      Row(children: [
        Expanded(
            child: Text('둘 다 계산하면',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: bC))),
        Text(
            fuelBenefit == 0
                ? '차이 없음'
                : '${wonF.format(fuelBenefit.abs())}원 ${fuelBenefit > 0 ? '절약' : '더 들어요'}',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, color: bC)),
      ]),
      if (extraMin > 0) ...[
        const SizedBox(height: 3),
        Row(children: [
          Expanded(
              child: Text('시간은', style: TextStyle(fontSize: 12, color: muted))),
          Text('$extraMin분 더 걸려요',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
        ]),
      ],
      if (showTotal) ...[
        const SizedBox(height: 3),
        Row(children: [
          Expanded(
              child: Text('시간까지 값으로 치면',
                  style: TextStyle(fontSize: 12, color: muted))),
          Text(
              netWon == 0
                  ? '차이 없음'
                  : '총 ${wonF.format(netWon.abs())}원 ${netWon > 0 ? '절약' : '더 들어요'}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: netWon > 0 ? green : (netWon < 0 ? red : ink))),
        ]),
      ],
      const SizedBox(height: 6),
      Text(verdict,
          style: TextStyle(
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: muted)),
    ]),
  );
}

Widget _costVerdictLine(String label, String value, Color muted, Color ink) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(width: 12),
        // value 에 주유소 풀네임이 들어올 수 있어(직접선택 비교) 폭 제한 + 줄바꿈 허용.
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
        ),
      ]),
    );

// ─── 다른 후보 섹션 ───────────────────────────────────────────────────────────

class _AltSection extends StatelessWidget {
  final List<dynamic> alternatives;
  final NumberFormat wonFmt;
  final void Function(dynamic altItem)? onSelect;
  final Map<String, dynamic>? selectedItem;

  const _AltSection({
    required this.alternatives,
    required this.wonFmt,
    this.onSelect,
    this.selectedItem,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 도달 불가(서버 unreachable=true) 후보는 아예 뺀다 — 어차피 못 가는 곳이
    // 리스트만 길게 만든다(형 확정). 이전엔 회색+⚠ 로 보여줬었음.
    final valid = alternatives
        .whereType<Map>()
        .where((m) => m['unreachable'] != true)
        .toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    final selectedId = selectedItem?['station'] is Map
        ? (selectedItem!['station'] as Map)['id']?.toString()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('다른 후보',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : const Color(0xFF1a1a1a))),
            const SizedBox(width: 6),
            Text('가격 순',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : const Color(0xFF999999))),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            // 다크: 라이트 라벤더 블록 대신 surface 계층 + 보라 힌트 보더
            color: isDark ? AppColors.darkSurface1 : _kAltBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color:
                    isDark ? _kSelected.withValues(alpha: 0.25) : _kAltBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: List.generate(valid.length, (idx) {
              final item = valid[idx];
              final st = item['station'] is Map ? item['station'] as Map : null;
              final name = st?['name']?.toString() ?? '';
              final addr = st?['address']?.toString() ?? '';
              final itemId = st?['id']?.toString();
              final price = _d(st?['price_won_per_liter']);
              final detourM = _i(item['detour_distance_m']);
              // 실질 절약(부가비용 뺀) 우선, 없으면 단순 절약 폴백.
              final savings = _fuelSavingsWon(item);
              final detourTimeMin = item['detour_is_none'] == true
                  ? 0
                  : (item['detour_time_min'] is num
                      ? item['detour_time_min'] as num
                      : null);
              final isLast = idx == valid.length - 1;
              final isSelected = selectedId != null && selectedId == itemId;
              // 고속도로 필터 ON + 잔량으로 도달 어려운 휴게소 (서버 unreachable=true).
              // primary 추천에선 이미 제외됐고, alt 풀에만 노출 — 사용자가 비교용으로 보되 시각적으로 명확히 구분.
              final isUnreachable = item['unreachable'] == true;

              final detourText = _detourAltListSubtitle(
                detourM: detourM,
                detourTimeMin: detourTimeMin,
                serverDetourIsNone: item['detour_is_none'] is bool
                    ? item['detour_is_none'] as bool
                    : null,
              );

              return Column(
                children: [
                  Container(
                    color: isUnreachable ? _kUnreachableBg : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          // 번호 뱃지 (선택 → 체크, 도달불가 → ⚠, 그 외 → 번호 보라톤)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? _kSelected
                                  : isUnreachable
                                      ? (isDark
                                          ? const Color(0x1FFFFFFF)
                                          : _kUnreachableChipBg)
                                      : (isDark
                                          ? _kSelected.withValues(alpha: 0.22)
                                          : _kAltBadgeBg),
                            ),
                            child: Center(
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 13, color: Colors.white)
                                  : isUnreachable
                                      ? const Icon(Icons.warning_amber_rounded,
                                          size: 14, color: _kUnreachableAccent)
                                      : Text('${idx + 1}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              // 다크: 밝은 보라 변형
                                              color: isDark
                                                  ? const Color(0xFFA292FF)
                                                  : _kAltBadgeText)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 이름 + 주소 + 정보
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? (isDark
                                                      ? const Color(0xFFA292FF)
                                                      : _kSelected)
                                                  : isUnreachable
                                                      ? _kUnreachableAccent
                                                      : (isDark
                                                          ? AppColors
                                                              .darkTextPrimary
                                                          : const Color(
                                                              0xFF1a1a1a)))),
                                    ),
                                    if (isUnreachable) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _kUnreachableChipBg,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: _kUnreachableAccent
                                                  .withValues(alpha: 0.35),
                                              width: 0.5),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded,
                                                size: 10,
                                                color: _kUnreachableAccent),
                                            SizedBox(width: 3),
                                            Text('잔량 부족',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  color: _kUnreachableAccent,
                                                )),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (addr.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(addr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF888888))),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (price != null)
                                      '${wonFmt.format(price.round())}원/L',
                                    detourText,
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.darkTextMuted
                                          : const Color(0xFF999999)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 절약 금액 (도달불가면 빨간 강조 안내)
                          isUnreachable
                              ? const Text(
                                  '도달 어려움',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _kUnreachableAccent,
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('추천보다',
                                        style: TextStyle(
                                            fontSize: 9,
                                            height: 1.1,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? AppColors.darkTextMuted
                                                : const Color(0xFF9CA3AF))),
                                    const SizedBox(height: 1),
                                    Text(
                                      savings == 0
                                          ? '가격 동일'
                                          : (savings > 0
                                              ? '${wonFmt.format(savings)}원 저렴'
                                              : '${wonFmt.format(-savings)}원 비쌈'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700,
                                        color: savings == 0
                                            ? (isDark
                                                ? AppColors.darkTextSecondary
                                                : const Color(0xFF6B7280))
                                            : (savings > 0
                                                ? const Color(0xFF3B82F6)
                                                : const Color(0xFFE24B4A)),
                                      ),
                                    ),
                                  ],
                                ),
                          const SizedBox(width: 8),
                          // 확인 버튼 — alt 섹션 톤(보라)으로 통일. 선택 상태는 강조 보라.
                          GestureDetector(
                            onTap: () =>
                                onSelect?.call(isSelected ? null : item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color:
                                    isSelected ? _kSelectedLight : _kAltBadgeBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? _kSelected : _kAltBorder,
                                  width: isSelected ? 1 : 0.5,
                                ),
                              ),
                              child: Text(
                                isSelected ? '선택됨' : '확인',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _kSelected,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast) Divider(height: 1, color: _kAltBorder),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── 공통 위젯 ────────────────────────────────────────────────────────────────

/// 우회 거리·시간을 한 줄에 몰아 넣지 않고 구분해 표시한다.
class _DetourStatsCell extends StatelessWidget {
  final int detourM;
  final num? detourTimeMin;

  const _DetourStatsCell({required this.detourM, required this.detourTimeMin});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1a1a1a),
    );
    final subStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: isDark ? AppColors.darkTextSecondary : const Color(0xFF546E7A),
    );
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999),
    );
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ..._valueWidgets(valueStyle, subStyle),
          const SizedBox(height: 3),
          Text('우회', textAlign: TextAlign.center, style: labelStyle),
        ],
      ),
    );
  }

  List<Widget> _valueWidgets(TextStyle valueStyle, TextStyle subStyle) {
    if (_detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin)) {
      return [
        Text('우회 없음', textAlign: TextAlign.center, style: valueStyle),
      ];
    }
    final m = _meaningfulDetourMinutes(detourTimeMin);
    final list = <Widget>[];
    if (detourM > 0) {
      final dist = detourM >= 1000
          ? '${(detourM / 1000).toStringAsFixed(1)} km'
          : '$detourM m';
      list.add(Text(dist, textAlign: TextAlign.center, style: valueStyle));
      list.add(const SizedBox(height: 4));
    }
    if (m != null) {
      list.add(Text(
        detourM > 0 ? '직행보다 +약 $m분' : '직행 대비 약 $m분 추가',
        textAlign: TextAlign.center,
        style: subStyle,
      ));
    } else {
      list.add(
        Text(
          '조금 우회',
          textAlign: TextAlign.center,
          style: subStyle,
        ),
      );
    }
    return list;
  }
}

class _NumCell extends StatelessWidget {
  final String value;
  final String label;
  final double? valueSize;

  const _NumCell({required this.value, required this.label, this.valueSize});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: valueSize ?? 15,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : const Color(0xFF1a1a1a),
              )),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : const Color(0xFF999999))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 비교 결과 Body (사용자 선택 비교 모드)
// ─────────────────────────────────────────────────────────────────────────────

// 통일된 색상 체계
const _kCompareWinner = Color(0xFF3B82F6); // 추천 (파랑 — 6a 단일 축, 주황 폐기)

class CompareResultBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final String destinationName;
  final ScrollController? scrollController;
  final NumberFormat wonFmt;
  final String? fuelLabel;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;

  /// 카드 탭 시 해당 station 데이터(via_route 포함) 전달 → 지도에 경로 그리기
  final void Function(Map<String, dynamic> stationData)? onCardTap;

  /// 이 결과가 계산된 기준 잔량 % — 상단 기준 칩으로 상시 노출
  final double? levelPercent;

  /// 1%당 주행가능 km (용량 × 효율 / 100) — 칩의 km 환산용
  final double? kmPerPercent;

  /// 기준 칩 탭 → 잔량 시트 → 저장 시 재비교
  final VoidCallback? onEditLevel;

  const CompareResultBody({
    super.key,
    required this.data,
    required this.destinationName,
    this.scrollController,
    required this.wonFmt,
    this.fuelLabel,
    this.originLat = 0,
    this.originLng = 0,
    this.destLat,
    this.destLng,
    this.onCardTap,
    this.levelPercent,
    this.kmPerPercent,
    this.onEditLevel,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final comparison = data['comparison'] is Map
        ? data['comparison'] as Map<String, dynamic>
        : null;
    final winner = comparison?['winner']?.toString() ?? 'station_a';
    final uiMessage = comparison?['ui_message']?.toString() ?? '';
    final savingsWon = _i(comparison?['savings_won']);
    final timeDiffMin = comparison?['time_diff_min'] is num
        ? (comparison!['time_diff_min'] as num).round()
        : null;
    final reasonCode = comparison?['reason_code']?.toString() ?? '';
    final computed = data['computed'] is Map
        ? data['computed'] as Map<String, dynamic>
        : null;
    final goalL = _d(computed?['goal_liters']);

    final stAData = data['station_a'] is Map
        ? data['station_a'] as Map<String, dynamic>
        : null;
    final stBData = data['station_b'] is Map
        ? data['station_b'] as Map<String, dynamic>
        : null;

    final sheetChildren = <Widget>[
      // ── 기준 칩 (3a) — 기준 잔량 + 주행가능거리, 탭하면 잔량 시트 ──
      if (levelPercent != null)
        LevelBasisCard(
            levelPercent: levelPercent!,
            kmPerPercent: kmPerPercent ?? 0,
            isEv: false,
            onEdit: onEditLevel),

      // 헤더
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kCompareWinner.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare_arrows_rounded,
                      size: 14, color: _kCompareWinner),
                  SizedBox(width: 4),
                  Text('비교 분석 결과',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kCompareWinner)),
                ],
              ),
            ),
            if (fuelLabel != null) ...[
              const SizedBox(width: 8),
              _FuelChip(label: fuelLabel!),
            ],
          ],
        ),
      ),

      // AI 메시지 (마크다운 지원)
      if (uiMessage.isNotEmpty) ...[
        _CompareMessageBanner(message: uiMessage),
        const SizedBox(height: 12),
      ],

      // 비교 테이블
      if (stAData != null && stBData != null)
        _UserCompareTable(
          stationAData: stAData,
          stationBData: stBData,
          winner: winner,
          savingsWon: savingsWon,
          timeDiffMin: timeDiffMin,
          reasonCode: reasonCode,
          costAnalysisData: comparison?['cost_analysis'] is Map
              ? Map<String, dynamic>.from(comparison!['cost_analysis'] as Map)
              : null,
          wonFmt: wonFmt,
          fuelLabel: fuelLabel,
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          onCardTap: onCardTap,
        ),

      // 기준 정보
      if (goalL != null) ...[
        const SizedBox(height: 16),
        Center(
          child: Text(
            '목표 주유량 약 ${goalL.toStringAsFixed(1)}L 기준',
            style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
          ),
        ),
      ],
    ];

    if (scrollController != null) {
      return CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedSheetHandleDelegate(),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver:
                SliverList(delegate: SliverChildListDelegate(sheetChildren)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: sheetChildren,
    );
  }
}

class _CompareMessageBanner extends StatelessWidget {
  final String message;
  const _CompareMessageBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final normalized =
        _normalizeMarkdownForKorean(message.replaceAll(r'\n', '\n'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? _kCompareWinner.withValues(alpha: 0.10)
            : const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? _kCompareWinner.withValues(alpha: 0.35)
                : const Color(0xFFB8CCFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _kCompareWinner.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 12, color: _kCompareWinner),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 경로 추천',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kCompareWinner)),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF1a1a1a)),
                    strong: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: _kCompareWinner,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 사용자 선택 비교 테이블 ──────────────────────────────────────────────────────

class _UserCompareTable extends StatelessWidget {
  final Map<String, dynamic> stationAData;
  final Map<String, dynamic> stationBData;
  final String winner;
  final int savingsWon;
  final int? timeDiffMin;
  final String reasonCode;
  final Map<String, dynamic>? costAnalysisData; // 서버 비용분해(판정 박스용)
  final NumberFormat wonFmt;
  final String? fuelLabel;
  final double originLat;
  final double originLng;
  final double? destLat;
  final double? destLng;
  final String destinationName;
  final void Function(Map<String, dynamic> stationData)? onCardTap;

  const _UserCompareTable({
    required this.stationAData,
    required this.stationBData,
    required this.winner,
    required this.savingsWon,
    required this.timeDiffMin,
    required this.reasonCode,
    this.costAnalysisData,
    required this.wonFmt,
    required this.fuelLabel,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    this.onCardTap,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final stA = stationAData['station'] is Map
        ? stationAData['station'] as Map<String, dynamic>
        : {};
    final stB = stationBData['station'] is Map
        ? stationBData['station'] as Map<String, dynamic>
        : {};

    final nameA = _stationNameFrom(stA);
    final nameB = _stationNameFrom(stB);
    final fuelA = _resolveFuelLabel(stA['fuel_type'], fallback: fuelLabel);
    final fuelB = _resolveFuelLabel(stB['fuel_type'], fallback: fuelLabel);
    final priceA = _d(stA['price_won_per_liter']);
    final priceB = _d(stB['price_won_per_liter']);
    final costA = _i(stationAData['expected_fuel_cost_won']);
    final costB = _i(stationBData['expected_fuel_cost_won']);
    final detourMinA = stationAData['detour_is_none'] == true
        ? 0
        : (stationAData['detour_time_min'] is num
            ? (stationAData['detour_time_min'] as num).round()
            : null);
    final detourMinB = stationBData['detour_is_none'] == true
        ? 0
        : (stationBData['detour_time_min'] is num
            ? (stationBData['detour_time_min'] as num).round()
            : null);

    final latA = _d(stA['lat']);
    final lngA = _d(stA['lng']);
    final latB = _d(stB['lat']);
    final lngB = _d(stB['lng']);

    final aIsWinner = winner == 'station_a';
    final bIsWinner = winner == 'station_b';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 추천 카드 (승자)
        _CompareRecommendCard(
          label: aIsWinner ? 'A' : 'B',
          name: aIsWinner ? nameA : nameB,
          price: aIsWinner ? priceA : priceB,
          cost: aIsWinner ? costA : costB,
          detourMin: aIsWinner ? detourMinA : detourMinB,
          stLat: aIsWinner ? latA : latB,
          stLng: aIsWinner ? lngA : lngB,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          originLat: originLat,
          originLng: originLng,
          wonFmt: wonFmt,
          onViewOnMap: onCardTap != null
              ? () => onCardTap!(aIsWinner ? stationAData : stationBData)
              : null,
        ),

        const SizedBox(height: 14),

        // 주유소 비교 — AI 결과와 동일한 2칼럼 카드 (왼쪽=비싼 쪽, 오른쪽=싼 쪽에 절약 표시)
        // 헤더는 _CompareCards 가 자체 렌더('주유소 비교'+유종칩) — 여기서 또 그리면 중복.
        Builder(builder: (context) {
          // 싼 쪽을 오른쪽 슬롯(절약 표시 지원)에 배치.
          final aCheaper =
              (priceA ?? double.infinity) <= (priceB ?? double.infinity);
          // 카드의 '↓ 절약'은 AI 카드와 동일하게 우회 연료비 차감 후 금액.
          // (하단 안내문 "부대비용까지 반영한 최종 차액" 과 일치, 시간값은 제외)
          final fuelAdjSavings = savingsWon -
              ((costAnalysisData?['detour_fuel_won'] as num?)?.round() ?? 0);
          final lName = aCheaper ? nameB : nameA;
          final rName = aCheaper ? nameA : nameB;
          return _CompareCards(
            onRouteName: lName,
            onRoutePrice: aCheaper ? priceB : priceA,
            onRouteCost: aCheaper ? costB : costA,
            onRouteDetourLabel: _detourText(aCheaper ? detourMinB : detourMinA),
            onRouteFuelLabel: aCheaper ? fuelB : fuelA,
            detourName: rName,
            detourPrice: aCheaper ? priceA : priceB,
            detourCost: aCheaper ? costA : costB,
            detourDetourLabel: _detourText(aCheaper ? detourMinA : detourMinB),
            detourFuelLabel: aCheaper ? fuelA : fuelB,
            savings: fuelAdjSavings > 0 ? fuelAdjSavings : 0,
            detourMins: timeDiffMin,
            // 오른쪽(싼 쪽)이 승자면 오른쪽 강조
            aiRecIsDetour: aCheaper ? aIsWinner : bIsWinner,
            tagLeft: aCheaper ? 'B 선택' : 'A 선택',
            tagRight: aCheaper ? 'A 선택' : 'B 선택',
            fuelLabel: fuelLabel,
            wonFmt: wonFmt,
            onViewOnMapRoute: onCardTap != null
                ? () => onCardTap!(aCheaper ? stationBData : stationAData)
                : null,
            onViewOnMapDetour: onCardTap != null
                ? () => onCardTap!(aCheaper ? stationAData : stationBData)
                : null,
            onRouteLat: aCheaper ? latB : latA,
            onRouteLng: aCheaper ? lngB : lngA,
            dtLat: aCheaper ? latA : latB,
            dtLng: aCheaper ? lngA : lngB,
            destLat: destLat,
            destLng: destLng,
            destinationName: destinationName,
            originLat: originLat,
            originLng: originLng,
          );
        }),

        const SizedBox(height: 12),

        // 상세 비교표 보기 — AI 결과와 동일한 팝업(카드 2장 + 우회 이득 판정 박스)
        Builder(builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return GestureDetector(
            onTap: () {
              final cards = <Map<String, dynamic>>[
                {
                  'name': nameA,
                  'brand': stA['brand']?.toString(),
                  'price': priceA?.round(),
                  'detour': detourMinA ?? 0,
                  'cost': costA,
                  'savings': aIsWinner ? savingsWon : 0,
                  'role': 'A 선택',
                  'isRec': aIsWinner,
                },
                {
                  'name': nameB,
                  'brand': stB['brand']?.toString(),
                  'price': priceB?.round(),
                  'detour': detourMinB ?? 0,
                  'cost': costB,
                  'savings': bIsWinner ? savingsWon : 0,
                  'role': 'B 선택',
                  'isRec': bIsWinner,
                },
              ];
              Map<String, dynamic>? cost;
              if (costAnalysisData != null) {
                cost = {
                  ...costAnalysisData!,
                  'subject': costAnalysisData!['cheaper_side'] == 'station_a'
                      ? nameA
                      : nameB,
                };
              }
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => _ComparisonDetailSheet(
                    cards: cards, cost: cost, wonFmt: wonFmt),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x14FFFFFF) : Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: isDark
                        ? AppColors.darkCardBorder
                        : const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_chart_outlined,
                      size: 15,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : const Color(0xFF555555)),
                  const SizedBox(width: 7),
                  Text('상세 비교표 보기',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : const Color(0xFF333333))),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  static String _detourText(int? detourMin) {
    if (detourMin == null || detourMin < _kDetourStartMinutes) return '우회 없음';
    return '+$detourMin분';
  }
}

// ─── 비교 추천 카드 ────────────────────────────────────────────────────────────

class _CompareRecommendCard extends StatelessWidget {
  final String label;
  final String name;
  final double? price;
  final int cost;
  final int? detourMin;
  final double? stLat, stLng, destLat, destLng;
  final String destinationName;
  final double originLat, originLng;
  final NumberFormat wonFmt;
  final VoidCallback? onViewOnMap;

  const _CompareRecommendCard({
    required this.label,
    required this.name,
    required this.price,
    required this.cost,
    required this.detourMin,
    required this.stLat,
    required this.stLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.wonFmt,
    this.onViewOnMap,
  });

  @override
  Widget build(BuildContext context) {
    final canNav =
        stLat != null && stLng != null && destLat != null && destLng != null;
    final isNegligible = detourMin == null || detourMin! < _kDetourStartMinutes;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : _kMarkerRecommendLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kMarkerRecommend, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _kMarkerRecommend,
                      borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 11, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('추천 $label',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 주유소명
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(name,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : const Color(0xFF1a1a1a))),
          ),

          // 수치 행
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0x14FFFFFF) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _RecStatCell(
                      icon: Icons.local_gas_station_rounded,
                      iconColor: _kMarkerRecommend,
                      value: price != null
                          ? '${wonFmt.format(price!.round())}원'
                          : '—',
                      label: '리터당 가격',
                      darkAdaptive: true,
                    ),
                    VerticalDivider(
                        width: 1,
                        color: isDark
                            ? AppColors.darkCardBorder
                            : const Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.access_time_rounded,
                      iconColor: isNegligible
                          ? _kMarkerRecommend
                          : const Color(0xFFE07B1D),
                      value: isNegligible
                          ? '우회 없음'
                          : (detourMin != null ? '+${detourMin}분' : '조금 우회'),
                      label: '직행 대비',
                      darkAdaptive: true,
                    ),
                    VerticalDivider(
                        width: 1,
                        color: isDark
                            ? AppColors.darkCardBorder
                            : const Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.payments_outlined,
                      iconColor: _kMarkerRecommend,
                      value: cost > 0 ? '${wonFmt.format(cost)}원' : '—',
                      label: '예상 주유비',
                      darkAdaptive: true,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 길안내 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: canNav
                    ? () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: name,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                          stopKind: '주유소',
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kMarkerRecommend,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.route_rounded, size: 16),
                label: const Text('경유 길안내',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
