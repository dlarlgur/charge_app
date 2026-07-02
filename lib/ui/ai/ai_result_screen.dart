import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/navigation_util.dart';
import '../../data/services/station_alias_service.dart';
import '../widgets/shared_widgets.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kSelected = Color(0xFF7B61FF);
const _kSelectedLight = Color(0xFFF5F2FF);
// 다른 후보 섹션 — 추천(주황) 카드와 시각적으로 구분되는 옅은 보라 톤.
const _kAltBg = Color(0xFFF7F4FF); // 카드 컨테이너 배경
const _kAltBorder = Color(0xFFE3DBF7); // 카드 컨테이너 border
const _kAltBadgeBg = Color(0xFFEDE7FF); // 일반 alt 번호 배지 배경
const _kAltBadgeText = Color(0xFF7B61FF); // 일반 alt 번호 배지 글자
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
const _kMarkerRecommend = Color(0xFFE8700A); // 추천 (주황)
const _kMarkerRecommendLight = Color(0xFFFFF3E0); // 추천 배경 (연한 주황)

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
        'detour_cost_won': rawSav - netSav,
        'net_benefit_won': netSav,
        'detour_fuel_won':
            sel['detour_fuel_won'] is num ? _i(sel['detour_fuel_won']) : null,
        'detour_extra_min':
            sel['detour_extra_min'] is num ? _i(sel['detour_extra_min']) : null,
        'verdict': netSav >= 0 ? 'detour_worth' : 'on_route_worth',
      };
    } else {
      final onR = toCard(d['on_route'], '경로상', choice == 'on_route');
      if (onR != null) cards.add(onR);
      final det = toCard(d['best_detour'], '우회', choice == 'best_detour');
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
      builder: (_) =>
          _ComparisonDetailSheet(cards: cards, cost: sheetCost, wonFmt: _wonFmt),
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

  @override
  Widget build(BuildContext context) {
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
    // 서버가 2번째 카드 노출 여부 결정 (추천보다 비싸기만 한 우회는 숨김). 누락 시 기본 표시.
    final showSecondary = rec?['show_secondary'] != false;
    // 서버가 경로상 후보 없을 때 최소 우회시간 후보를 가상 baseline 으로 승격
    // → "경로상 최저가" 라벨을 "근거리 우회"로 분기
    final isOnRouteVirtual = onRoute?['is_on_route_virtual'] == true;
    final onRouteLabel = isOnRouteVirtual ? '근거리 우회' : '경로상 최저가';
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
        tagColor: const Color(0xFFE8700A), // 주황
        isAiRec: true,
        isUserSelected: false,
        rawData: onRoute,
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
            isDualDetour ? const Color(0xFF888888) : const Color(0xFFE8700A),
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
        tag: '우회 최저가',
        tagColor: const Color(0xFF1D6FE0), // 파랑
        isAiRec: false,
        isUserSelected: false,
        rawData: bestDetour,
      );
    }

    final sheetChildren = <Widget>[
      // ── 유종 칩 ──
      if (widget.fuelLabel != null) ...[
        _FuelChip(label: widget.fuelLabel!),
        const SizedBox(height: 10),
      ],

      // ── 도달 가능 범위 안내 (상단 노출) ──
      if (reachable != null && reachable['enabled'] == true) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFD95A), width: 1),
          ),
          child: Row(
            children: const [
              Icon(Icons.local_gas_station, size: 15, color: Color(0xFF856404)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '현재 연료로 갈 수 있는 거리 안의 주유소만 표시했어요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],

      // ── AI 메시지 ──
      // 선호 브랜드 폴백 안내 — 고른 브랜드가 경로에 없어 전체에서 추천한 경우.
      if (rec?['brand_filter'] is Map &&
          (rec!['brand_filter'] as Map)['fallback'] == true) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE6A6)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 17, color: Color(0xFF8A6D3B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '선택한 선호 브랜드가 이 경로엔 없어 전체 주유소에서 추천했어요.',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF8A6D3B), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (uiMessage.isNotEmpty) ...[
        _AiMessageBanner(message: uiMessage),
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
          showDetour: showDetour,
          detourName: showDetour ? _stationNameFrom(detourSt) : '',
          detourBrand: detourSt?['brand']?.toString(),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE6A6)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFF8A6D3B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '현재 연료로 목적지 도달이 가능해 지금은 추천 주유소를 표시하지 않습니다.',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF8A6D3B), height: 1.4),
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
  if (item['real_savings_won'] is num) return p(item['real_savings_won']); // 구서버 폴백
  if (item['savings_vs_primary_won'] is num) return p(item['savings_vs_primary_won']);
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
  const _AiMessageBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final normalized =
        _normalizeMarkdownForKorean(message.replaceAll(r'\n', '\n'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // 주유 AI 경로추천 배너 — 파랑 톤 (추천카드 주황과 구분).
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E4FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EEFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 12, color: Color(0xFF1D6FE0)),
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
                        color: Color(0xFF1D6FE0))),
                const SizedBox(height: 6),
                MarkdownBody(
                  data: normalized,
                  shrinkWrap: true,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(
                        fontSize: 13, height: 1.5, color: Color(0xFF1a1a1a)),
                    strong: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
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
  final bool showDetour;
  final String detourName;
  final String? detourBrand;
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
    required this.showDetour,
    required this.detourName,
    this.detourBrand,
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
            detourName: detourName,
            detourPrice: detourPrice,
            detourCost: detourCost,
            detourDetourLabel: _detourLabel(dtDetourM, dtDetourTimeMin),
            detourFuelLabel:
                _resolveFuelLabel(detourFuelType, fallback: fuelLabel),
            savings: dtSavings,
            detourMins: dtDetourMins,
            aiRecIsDetour: aiRecIsDetour,
            isDualDetour: isDualDetour,
            isOnRouteVirtual: isOnRouteVirtual,
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

class _RecommendedCard extends StatelessWidget {
  final String name;
  final String? brand;
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

  const _RecommendedCard({
    required this.name,
    this.brand,
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

  @override
  Widget build(BuildContext context) {
    final canNav =
        stLat != null && stLng != null && destLat != null && destLng != null;
    final isNegligible =
        _detourIsNegligible(detourM: detourM, detourTimeMin: detourTimeMin);
    final detourMins = _meaningfulDetourMinutes(detourTimeMin);

    return Container(
      decoration: BoxDecoration(
        color: _kMarkerRecommendLight,
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
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCCEEDE)),
                  ),
                  child: Text(
                    isDetour ? '우회 최저가' : '경로상 최저가',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF444444)),
                  ),
                ),
                const Spacer(),
                if (onViewOnMap != null)
                  GestureDetector(
                    onTap: onViewOnMap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCCEEDE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 13, color: _kPrimary),
                          SizedBox(width: 3),
                          Text('지도',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _kPrimary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 브랜드 로고 + 주유소명
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                if (brand != null && brand!.isNotEmpty) ...[
                  BrandLogo(brand: brand!, stationName: name),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1a1a1a))),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 핵심 수치 3개
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCCEEDE)),
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
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.access_time_rounded,
                      iconColor: isNegligible
                          ? _kMarkerRecommend
                          : const Color(0xFFE07B1D),
                      value: isNegligible
                          ? '우회 없음'
                          : (detourMins != null ? '+${detourMins}분' : '조금 우회'),
                      label: '직행 대비',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.payments_outlined,
                      iconColor: _kMarkerRecommend,
                      value: cost > 0 ? '${wonFmt.format(cost)}원' : '—',
                      label: '예상 주유비',
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

class _RecStatCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _RecStatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
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
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1a1a1a))),
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
  final String detourName;
  final double? detourPrice;
  final int detourCost;
  final String detourDetourLabel;
  final String detourFuelLabel;
  final int savings;
  final int? detourMins;
  final bool aiRecIsDetour;
  final bool isDualDetour;
  final bool isOnRouteVirtual;
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
    required this.detourName,
    required this.detourPrice,
    required this.detourCost,
    required this.detourDetourLabel,
    required this.detourFuelLabel,
    required this.savings,
    required this.detourMins,
    required this.aiRecIsDetour,
    this.isDualDetour = false,
    this.isOnRouteVirtual = false,
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

  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasOnRoute = onRouteName.trim().isNotEmpty;
    final hasDetour = detourName.trim().isNotEmpty;
    final detourIsWinner = aiRecIsDetour;
    final labelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);

    VoidCallback? navTo(double? lat, double? lng, String name) {
      if (lat == null || lng == null || destLat == null || destLng == null) {
        return null;
      }
      return () => showViaWaypointNavigationSheet(
            context,
            originLat: originLat,
            originLng: originLng,
            waypointLat: lat,
            waypointLng: lng,
            waypointName: name,
            destinationLat: destLat!,
            destinationLng: destLng!,
            destinationName: destinationName,
          );
    }

    final cols = <Widget>[];
    if (hasOnRoute) {
      cols.add(_col(
        isDark: isDark,
        tag: isOnRouteVirtual ? '근거리 우회' : '경로상 최저가',
        isWinner: !detourIsWinner,
        name: onRouteName,
        price: onRoutePrice,
        cost: onRouteCost,
        detourLabel: onRouteDetourLabel,
        savingsText: null,
        onMap: onViewOnMapRoute,
        onNav: navTo(onRouteLat, onRouteLng, onRouteName),
      ));
    }
    if (hasDetour) {
      cols.add(_col(
        isDark: isDark,
        tag: '우회 최저가',
        isWinner: detourIsWinner,
        name: detourName,
        price: detourPrice,
        cost: detourCost,
        detourLabel: detourDetourLabel,
        savingsText: savings > 0 ? '${wonFmt.format(savings)}원 ↓' : null,
        onMap: onViewOnMapDetour,
        onNav: navTo(dtLat, dtLng, detourName),
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
          cols.first,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isWinner)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: _amber, borderRadius: BorderRadius.circular(5)),
                  child: const Text('추천',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
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

class _TableRow extends StatelessWidget {
  final bool isHeader;
  final String? label;
  final String? left;
  final String mid;
  final String right;
  final bool midHighlight;
  final bool rightHighlight;
  final Widget? midButton;
  final Widget? rightButton;
  final Widget? midNavButton;
  final Widget? rightNavButton;

  const _TableRow({
    this.isHeader = false,
    this.label,
    this.left,
    required this.mid,
    required this.right,
    required this.midHighlight,
    required this.rightHighlight,
    this.midButton,
    this.rightButton,
    this.midNavButton,
    this.rightNavButton,
  });

  @override
  Widget build(BuildContext context) {
    // midHighlight/rightHighlight: 추천(주황) 컬러를 줄 쪽을 의미하고,
    // 나머지 쪽(비승자)은 비교(파랑)로 통일한다.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final midColor = isHeader
        ? headerTextColor
        : (midHighlight ? _kMarkerRecommend : _kCompareLoser);
    final rightColor = isHeader
        ? headerTextColor
        : (rightHighlight ? _kMarkerRecommend : _kCompareLoser);
    // 다크: 헤더/라벨 열은 카드 보다 살짝 어둡게, 비강조 셀은 파란 ghost tint.
    final labelBg = isDark ? const Color(0x0AFFFFFF) : const Color(0xFFFAFAFA);
    final labelText =
        isDark ? AppColors.darkTextMuted : const Color(0xFF888888);
    final headerCellBg = isDark ? AppColors.darkCard : Colors.white;
    final winnerCellBg = isDark
        ? _kMarkerRecommend.withValues(alpha: 0.16)
        : _kMarkerRecommendLight;
    final loserCellBg = isDark
        ? _kCompareLoser.withValues(alpha: 0.16)
        : const Color(0xFFEEF4FF);
    final dividerColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFF0F0F0);

    return IntrinsicHeight(
      child: Row(
        children: [
          // 라벨 열
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: labelBg,
            child: Text(
              isHeader ? '' : (label ?? ''),
              style: TextStyle(
                  fontSize: 10, color: labelText, fontWeight: FontWeight.w500),
            ),
          ),
          VerticalDivider(width: 1, color: dividerColor),
          // 경로상 열
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isHeader
                  ? headerCellBg
                  : (midHighlight ? winnerCellBg : loserCellBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mid,
                    style: TextStyle(
                      fontSize: isHeader ? 10 : 12,
                      fontWeight: (isHeader || midHighlight)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: midColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (midButton != null || midNavButton != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (midButton != null) midButton!,
                          if (midNavButton != null) midNavButton!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: dividerColor),
          // 우회 열
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isHeader
                  ? headerCellBg
                  : (rightHighlight ? winnerCellBg : loserCellBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    right,
                    style: TextStyle(
                      fontSize: isHeader ? 10 : 12,
                      fontWeight: (isHeader || rightHighlight)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: rightColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rightButton != null || rightNavButton != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (rightButton != null) rightButton!,
                          if (rightNavButton != null) rightNavButton!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 옵션 카드 ────────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final bool isAiRec;
  final bool isUserSelected;
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
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 13, color: Color(0xFF666666)),
                          SizedBox(width: 3),
                          Text('지도',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF666666))),
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
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.savings_outlined,
                            size: 15, color: Color(0xFF1D6FE0)),
                        const SizedBox(width: 6),
                        Text(
                          '경로상 대비 ${wonFmt.format(extraInfo!.savings)}원 절약',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D6FE0)),
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
                    ? () => showViaWaypointNavigationSheet(
                          context,
                          originLat: originLat,
                          originLng: originLng,
                          waypointLat: stLat!,
                          waypointLng: stLng!,
                          waypointName: stName,
                          destinationLat: destLat!,
                          destinationLng: destLng!,
                          destinationName: destinationName,
                        )
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
    const recColor = Color(0xFF1D6FE0);
    final lineColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEF1F5);
    final c1 = cards[0];
    final c2 = cards.length > 1 ? cards[1] : null;

    Color colColor(Map<String, dynamic> c) =>
        c['isRec'] == true ? recColor : ink;
    String detTxt(Map<String, dynamic> c) {
      final d = c['detour'] as int? ?? 0;
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

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
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
              const Icon(Icons.compare_arrows_rounded,
                  size: 18, color: recColor),
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
              Expanded(child: _head(c1, ink, recColor)),
              if (c2 != null) Expanded(child: _head(c2, ink, recColor)),
            ]),
            const SizedBox(height: 10),
            line(),
            mRow(
                '리터당 가격',
                '${wonFmt.format((c1['price'] as double).round())}원',
                c2 != null
                    ? '${wonFmt.format((c2['price'] as double).round())}원'
                    : null,
                big: true),
            line(),
            mRow('우회 시간', detTxt(c1), c2 != null ? detTxt(c2) : null),
            line(),
            mRow('예상 주유비', _won(c1['cost'] as int?),
                c2 != null ? _won(c2['cost'] as int?) : null),
            if (cost != null) ...[
              const SizedBox(height: 14),
              _costBox(cost!, ink, muted, isDark),
            ],
          ],
        ),
      ),
    );
  }

  String _won(int? n) => (n != null && n > 0) ? '${wonFmt.format(n)}원' : '-';

  Widget _head(Map<String, dynamic> c, Color ink, Color recColor) {
    final isRec = c['isRec'] == true;
    final role = c['role'] as String? ?? '';
    final brand = (c['brand'] as String?) ?? '';
    final roleColor =
        role == '경로상' ? const Color(0xFFE8700A) : const Color(0xFF1D6FE0);
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

  // 비용 판정 박스 — 절약 − 우회비용 = 순이득.
  Widget _costBox(
      Map<String, dynamic> ca, Color ink, Color muted, bool isDark) {
    int gi(String k) {
      final v = ca[k];
      if (v is num) return v.round();
      return int.tryParse('${v ?? 0}') ?? 0;
    }

    final savings = gi('savings_won'); // 순수 가격차(연료값)
    final worth = ca['verdict'] == 'detour_worth';
    // 시간값(원)을 돈에 안 섞고 '연료 기준 이득 + 우회 시간(분)'으로 분리 표시.
    final fuelWon = ca['detour_fuel_won'] is num ? gi('detour_fuel_won') : 0;
    final extraMin = ca['detour_extra_min'] is num ? gi('detour_extra_min') : 0;
    final fuelBenefit = savings - fuelWon; // 연료 기준 순이득(추가연료비까지 뺀 순수 돈)
    if (savings <= 0 && fuelWon <= 0 && extraMin <= 0) {
      return const SizedBox.shrink();
    }
    const green = Color(0xFF1D9E75);
    const orange = Color(0xFFE8700A);
    const red = Color(0xFFE24B4A);
    final c = worth ? green : orange; // 헤더/판정 색
    final bC = fuelBenefit >= 0 ? green : red; // 이득/손해 색
    final wonF = wonFmt;
    // 판정 문구 — 시간은 분으로만, 이득은 연료 기준.
    String verdict;
    if (extraMin <= 0) {
      verdict = fuelBenefit > 0
          ? '추가 우회 없이 더 저렴해 우회를 추천해요'
          : '추가 시간·연료까지 감안하면 경로상이 유리해요';
    } else if (worth) {
      verdict =
          '$extraMin분 더 걸려도 연료 기준 ${wonF.format(fuelBenefit)}원 절약돼 우회할 만해요';
    } else if (fuelBenefit > 0) {
      verdict =
          '연료 기준 ${wonF.format(fuelBenefit)}원 저렴하지만, $extraMin분 더 우회할 만큼 차이가 크진 않아 경로상을 추천해요';
    } else {
      verdict = '추가 연료비까지 감안하면 오히려 더 들어 경로상을 추천해요';
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.withValues(alpha: 0.22)),
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
        _costLine('가격 절약(연료차)', '+${wonF.format(savings)}원', muted, ink),
        if (fuelWon > 0)
          _costLine('추가 연료비', '−${wonF.format(fuelWon)}원', muted, ink),
        Divider(height: 14, color: c.withValues(alpha: 0.2)),
        Row(children: [
          Expanded(
              child: Text('연료 기준',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: bC))),
          Text(
              '${wonF.format(fuelBenefit.abs())}원 ${fuelBenefit >= 0 ? '절약' : '더 비쌈'}',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: bC)),
        ]),
        if (extraMin > 0) ...[
          const SizedBox(height: 3),
          Row(children: [
            Expanded(
                child: Text('우회 시간',
                    style: TextStyle(fontSize: 12, color: muted))),
            Text('+$extraMin분',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
          ]),
        ],
        const SizedBox(height: 6),
        Text(verdict,
            style: TextStyle(
                fontSize: 11, height: 1.35, fontWeight: FontWeight.w600, color: muted)),
      ]),
    );
  }

  Widget _costLine(String label, String value, Color muted, Color ink) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(label, style: TextStyle(fontSize: 12, color: muted))),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
        ]),
      );
}

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
    final valid = alternatives.whereType<Map>().toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    final selectedId = selectedItem?['station'] is Map
        ? (selectedItem!['station'] as Map)['id']?.toString()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('다른 후보',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a1a1a))),
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
            color: _kAltBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kAltBorder),
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
                                      ? _kUnreachableChipBg
                                      : _kAltBadgeBg,
                            ),
                            child: Center(
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 13, color: Colors.white)
                                  : isUnreachable
                                      ? const Icon(Icons.warning_amber_rounded,
                                          size: 14, color: _kUnreachableAccent)
                                      : Text('${idx + 1}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _kAltBadgeText)),
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
                                                  ? _kSelected
                                                  : isUnreachable
                                                      ? _kUnreachableAccent
                                                      : const Color(
                                                          0xFF1a1a1a))),
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
                                      savings >= 0
                                          ? '${wonFmt.format(savings)}원 저렴'
                                          : '${wonFmt.format(-savings)}원 비쌈',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700,
                                        color: savings >= 0
                                            ? const Color(0xFF1D9E75)
                                            : const Color(0xFFE24B4A),
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
const _kCompareWinner = Color(0xFFE8700A); // 추천 (주황)
const _kCompareLoser = Color(0xFF1D6FE0); // 비교 대상 (파랑)

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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8CCFF)),
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
                    p: const TextStyle(
                        fontSize: 13, height: 1.5, color: Color(0xFF1a1a1a)),
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

        const SizedBox(height: 12),

        // 비교 테이블
        _UserComparisonTable(
          nameA: nameA,
          nameB: nameB,
          priceA: priceA,
          priceB: priceB,
          fuelA: fuelA,
          fuelB: fuelB,
          costA: costA,
          costB: costB,
          detourMinA: detourMinA,
          detourMinB: detourMinB,
          latA: latA,
          lngA: lngA,
          latB: latB,
          lngB: lngB,
          aIsWinner: aIsWinner,
          bIsWinner: bIsWinner,
          savingsWon: savingsWon,
          timeDiffMin: timeDiffMin,
          fuelLabel: fuelLabel,
          wonFmt: wonFmt,
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          destinationName: destinationName,
          onViewOnMapA:
              onCardTap != null ? () => onCardTap!(stationAData) : null,
          onViewOnMapB:
              onCardTap != null ? () => onCardTap!(stationBData) : null,
        ),
      ],
    );
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

    return Container(
      decoration: BoxDecoration(
        color: _kMarkerRecommendLight,
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
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a1a1a))),
          ),

          // 수치 행
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.access_time_rounded,
                      iconColor: isNegligible
                          ? _kMarkerRecommend
                          : const Color(0xFFE07B1D),
                      value: isNegligible
                          ? '우회 없음'
                          : (detourMin != null ? '+${detourMin}분' : '조금 우회'),
                      label: '직행 대비',
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFDDDDDD)),
                    _RecStatCell(
                      icon: Icons.payments_outlined,
                      iconColor: _kMarkerRecommend,
                      value: cost > 0 ? '${wonFmt.format(cost)}원' : '—',
                      label: '예상 주유비',
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

// ─── 사용자 비교 테이블 ────────────────────────────────────────────────────────

class _UserComparisonTable extends StatelessWidget {
  final String nameA, nameB;
  final double? priceA, priceB;
  final String fuelA, fuelB;
  final int costA, costB;
  final int? detourMinA, detourMinB;
  final double? latA, lngA, latB, lngB;
  final bool aIsWinner, bIsWinner;
  final int savingsWon;
  final int? timeDiffMin;
  final String? fuelLabel;
  final NumberFormat wonFmt;
  final double originLat, originLng;
  final double? destLat, destLng;
  final String destinationName;
  final VoidCallback? onViewOnMapA;
  final VoidCallback? onViewOnMapB;

  const _UserComparisonTable({
    required this.nameA,
    required this.nameB,
    required this.priceA,
    required this.priceB,
    required this.fuelA,
    required this.fuelB,
    required this.costA,
    required this.costB,
    required this.detourMinA,
    required this.detourMinB,
    required this.latA,
    required this.lngA,
    required this.latB,
    required this.lngB,
    required this.aIsWinner,
    required this.bIsWinner,
    required this.savingsWon,
    required this.timeDiffMin,
    required this.fuelLabel,
    required this.wonFmt,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.destinationName,
    this.onViewOnMapA,
    this.onViewOnMapB,
  });

  String _detourLabel(int? detourMin) {
    if (detourMin == null || detourMin < _kDetourStartMinutes) return '우회 없음';
    return '+${detourMin}분';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tableBg = isDark ? AppColors.darkCard : Colors.white;
    final tableBorder =
        isDark ? AppColors.darkCardBorder : const Color(0xFFEEEEEE);
    final titleColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF333333);
    final iconColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    return Container(
      decoration: BoxDecoration(
        color: tableBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tableBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.compare_arrows_rounded, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Text('상세 비교',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: titleColor)),
                if (fuelLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5FBF8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCCEEDE)),
                    ),
                    child: Text(fuelLabel!,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _kPrimary)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 표 헤더
          _TableRow(
            isHeader: true,
            left: '',
            mid: '주유소 A',
            right: '주유소 B',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 주유소명
          _TableRow(
            label: '주유소',
            left: null,
            mid: nameA,
            right: nameB,
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
            midButton: onViewOnMapA != null
                ? GestureDetector(
                    onTap: onViewOnMapA,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color:
                                (aIsWinner ? _kMarkerRecommend : _kCompareLoser)
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 10,
                              color: aIsWinner
                                  ? _kMarkerRecommend
                                  : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: aIsWinner
                                      ? _kMarkerRecommend
                                      : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightButton: onViewOnMapB != null
                ? GestureDetector(
                    onTap: onViewOnMapB,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color:
                                (bIsWinner ? _kMarkerRecommend : _kCompareLoser)
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 10,
                              color: bIsWinner
                                  ? _kMarkerRecommend
                                  : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('지도보기',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: bIsWinner
                                      ? _kMarkerRecommend
                                      : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            midNavButton: latA != null &&
                    lngA != null &&
                    destLat != null &&
                    destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                      context,
                      originLat: originLat,
                      originLng: originLng,
                      waypointLat: latA!,
                      waypointLng: lngA!,
                      waypointName: nameA,
                      destinationLat: destLat!,
                      destinationLng: destLng!,
                      destinationName: destinationName,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (aIsWinner ? _kMarkerRecommend : _kCompareLoser)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color:
                                (aIsWinner ? _kMarkerRecommend : _kCompareLoser)
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded,
                              size: 10,
                              color: aIsWinner
                                  ? _kMarkerRecommend
                                  : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: aIsWinner
                                      ? _kMarkerRecommend
                                      : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
            rightNavButton: latB != null &&
                    lngB != null &&
                    destLat != null &&
                    destLng != null
                ? GestureDetector(
                    onTap: () => showViaWaypointNavigationSheet(
                      context,
                      originLat: originLat,
                      originLng: originLng,
                      waypointLat: latB!,
                      waypointLng: lngB!,
                      waypointName: nameB,
                      destinationLat: destLat!,
                      destinationLng: destLng!,
                      destinationName: destinationName,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (bIsWinner ? _kMarkerRecommend : _kCompareLoser)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color:
                                (bIsWinner ? _kMarkerRecommend : _kCompareLoser)
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation_rounded,
                              size: 10,
                              color: bIsWinner
                                  ? _kMarkerRecommend
                                  : _kCompareLoser),
                          const SizedBox(width: 2),
                          Text('경로안내',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: bIsWinner
                                      ? _kMarkerRecommend
                                      : _kCompareLoser)),
                        ],
                      ),
                    ),
                  )
                : null,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 리터당 가격
          _TableRow(
            label: '리터당',
            left: null,
            mid: priceA != null ? '${wonFmt.format(priceA!.round())}원' : '—',
            right: priceB != null ? '${wonFmt.format(priceB!.round())}원' : '—',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          _TableRow(
            label: '유종',
            left: null,
            mid: fuelA,
            right: fuelB,
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 예상 주유비
          _TableRow(
            label: '예상 주유비',
            left: null,
            mid: costA > 0 ? '${wonFmt.format(costA)}원' : '—',
            right: costB > 0 ? '${wonFmt.format(costB)}원' : '—',
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 추가 시간
          _TableRow(
            label: '우회 시간',
            left: null,
            mid: _detourLabel(detourMinA),
            right: _detourLabel(detourMinB),
            midHighlight: aIsWinner,
            rightHighlight: bIsWinner,
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 결론 배너
          if (savingsWon > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF5FBF8),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 15, color: _kMarkerRecommend),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF1a1a1a)),
                        children: [
                          TextSpan(
                            text: aIsWinner ? '주유소 A' : '주유소 B',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _kMarkerRecommend),
                          ),
                          const TextSpan(text: '가 '),
                          TextSpan(
                            text: '${wonFmt.format(savingsWon)}원',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _kMarkerRecommend),
                          ),
                          const TextSpan(text: ' 더 저렴해요'),
                          if (timeDiffMin != null && timeDiffMin! > 0)
                            TextSpan(text: ' · 대신 ${timeDiffMin}분 더 소요'),
                        ],
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
