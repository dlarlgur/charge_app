import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/api_constants.dart' show AppConstants;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/alert_service.dart';
import '../../data/services/favorite_service.dart';
import '../../data/services/station_alias_service.dart';
import '../../data/services/widget_service.dart';
import '../../providers/providers.dart' show favoritesProvider;
import '../widgets/shared_widgets.dart' show showFuelTypeAlertSheet, BrandLogo;

// gas_detail.html 디자인 토큰 — 헤더/가격/그래프 카드 공용.
// 길안내·즐겨찾기·알림 액션만 앱 기존 AppColors.gasBlue 사용, 그 외는 HTML 양식 색.
const _kInk = Color(0xFF0F172A);
const _kInk2 = Color(0xFF334155);
const _kMuted = Color(0xFF64748B);
const _kMute2 = Color(0xFF94A3B8);
const _kLine = Color(0xFFE2E8F0);
const _kLineSoft = Color(0xFFF1F5F9);
const _kBg = Color(0xFFF5F6F8);
const _kCard = Color(0xFFFFFFFF);
// 유종별 — HTML 양식
const _kFuelRegular = Color(0xFF2563EB); // 휘발유
const _kFuelPremium = Color(0xFFF59E0B); // 고급휘발유
const _kFuelDiesel  = Color(0xFF10B981); // 경유
const _kFuelLpg     = Color(0xFF7C3AED); // LPG (HTML 외 추가)
const _kGreen = Color(0xFF047857);
const _kGreenBg = Color(0xFFECFDF5);
const _kRed = Color(0xFFB91C1C);
const _kRedBg = Color(0xFFFEF2F2);

enum _ChipTone { up, down }

// ─── 풀스크린 라우트 래퍼 ───────────────────────────────────────────────────
class GasDetailScreen extends ConsumerStatefulWidget {
  final String stationId;
  final GasStation? station;
  const GasDetailScreen({super.key, required this.stationId, this.station});
  @override
  ConsumerState<GasDetailScreen> createState() => _GasDetailScreenState();
}

class _GasDetailScreenState extends ConsumerState<GasDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('주유소 상세')),
      body: GasDetailContent(
        stationId: widget.stationId,
        station: widget.station,
      ),
    );
  }
}

// ─── 재사용 가능한 상세 컨텐츠 (풀스크린 + 지도 시트 공용) ─────────────────
class GasDetailContent extends ConsumerStatefulWidget {
  final String stationId;
  final GasStation? station;
  final ScrollController? sheetController;
  final bool sheetMode;
  const GasDetailContent({
    super.key,
    required this.stationId,
    this.station,
    this.sheetController,
    this.sheetMode = false,
  });
  @override
  ConsumerState<GasDetailContent> createState() => _GasDetailContentState();
}

class _GasDetailContentState extends ConsumerState<GasDetailContent> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  // 알림 / 즐겨찾기
  late bool _isFavorite;
  late bool _isAlarm;

  // 섹션 스크롤
  late final ScrollController _scroll;
  final GlobalKey _kPrice = GlobalKey();
  final GlobalKey _kStation = GlobalKey();
  int _activeTab = 0;

  // 가격 추이 차트 상태 — 첫 로딩은 4w 기본.
  String _chartPeriod = '4w';
  Map<String, dynamic>? _chartData;
  bool _chartLoading = false;

  static const List<String> _tabLabels = ['요금', '주유소 정보'];
  List<GlobalKey> get _sectionKeys => [_kPrice, _kStation];

  static const List<String> _fuelOrder = ['B027', 'B034', 'D047', 'K015'];
  static const Map<String, String> _fuelLabel = {
    'B027': '휘발유', 'B034': '고급휘발유', 'D047': '경유', 'K015': 'LPG',
  };

  // 유종별 색상 (HTML 양식)
  static Color _fuelColor(String code) {
    switch (code) {
      case 'B027': return _kFuelRegular;
      case 'B034': return _kFuelPremium;
      case 'D047': return _kFuelDiesel;
      case 'K015': return _kFuelLpg;
      default:     return AppColors.gasBlue;
    }
  }

  // 유종별 배경 (price tag 배경) — HTML 양식
  static Color _fuelBg(String code) {
    switch (code) {
      case 'B027': return const Color(0xFFEFF6FF);
      case 'B034': return const Color(0xFFFEF3C7);
      case 'D047': return const Color(0xFFECFDF5);
      case 'K015': return const Color(0xFFF3E8FF);
      default:     return _kLineSoft;
    }
  }

  @override
  void initState() {
    super.initState();
    _isFavorite = FavoriteService.isFavorite(widget.stationId, 'gas');
    _isAlarm = AlertService().isSubscribed(widget.stationId);
    AlertService().subsChanged.addListener(_onSubsChanged);
    _scroll = widget.sheetController ?? ScrollController();
    _scroll.addListener(_onScroll);
    _loadDetail();
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_onSubsChanged);
    _scroll.removeListener(_onScroll);
    if (widget.sheetController == null) _scroll.dispose();
    super.dispose();
  }

  void _onSubsChanged() {
    if (mounted) setState(() => _isAlarm = AlertService().isSubscribed(widget.stationId));
  }

  Future<void> _editAlias(String stationId, String originalName) async {
    final current = StationAliasService.getGas(stationId) ?? '';
    final controller = TextEditingController(text: current);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('주유소 별칭'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '원본: $originalName',
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: StationAliasService.maxLength,
                decoration: const InputDecoration(
                  hintText: '예: 우리동네 알뜰',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
          actions: [
            if (current.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('__delete__'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('삭제'),
              ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    if (result == '__delete__') {
      await StationAliasService.removeGas(stationId);
    } else {
      await StationAliasService.setGas(stationId, result);
    }
    if (mounted) {
      setState(() {});
      ref.read(favoritesProvider.notifier).refresh();
      WidgetService.updateGasWidget();
    }
  }

  // 사용자가 온보딩에서 설정한 차량 유종 — today chips/순위 기준.
  // Hive box `keyAiFuelType` 에 'B027'/'D047'/'B034'/'C004'/'K015' 양식으로 저장.
  String get _userFuelCode {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final raw = box.get(AppConstants.keyAiFuelType, defaultValue: 'B027');
      final code = raw?.toString() ?? 'B027';
      return ['B027', 'D047', 'B034', 'C004', 'K015'].contains(code) ? code : 'B027';
    } catch (_) {
      return 'B027';
    }
  }

  static const Map<String, String> _fuelLabelByCode = {
    'B027': '휘발유', 'B034': '고급휘발유', 'D047': '경유', 'C004': 'LPG', 'K015': '등유',
  };

  Future<void> _loadDetail() async {
    try {
      // 사용자 유종을 fuelType 쿼리로 전달 → 서버가 region_rank/price 를 그 유종 기준으로 산출.
      final data = await ApiService().getGasStationDetail(widget.stationId, fuelType: _userFuelCode);
      if (mounted) setState(() { _detail = data; _loading = false; });
      // detail 로드 후 차트 미리 fetch (4w 기본)
      _loadChart(_chartPeriod);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChart(String period) async {
    setState(() { _chartPeriod = period; _chartLoading = true; });
    try {
      // _detail 의 availableFuelTypes 중 그릴 만한 유종만 전달.
      // 그래프는 휘발유/고급/경유 3종이 표준 (HTML 양식). LPG/등유는 사용자가 보기 헷갈리므로 제외.
      final available = ((_detail?['availableFuelTypes'] as List?) ?? const [])
          .map((e) => e.toString()).toSet();
      final fuels = ['B027', 'B034', 'D047'].where(available.contains).toList();
      if (fuels.isEmpty) {
        if (mounted) setState(() { _chartData = null; _chartLoading = false; });
        return;
      }
      final data = await ApiService().getGasPriceHistory(
        widget.stationId, period: period, fuels: fuels,
      );
      if (mounted) setState(() { _chartData = data; _chartLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _chartData = null; _chartLoading = false; });
    }
  }

  void _toggleFavorite() {
    final d = _detail;
    final name = d?['OS_NM'] ?? d?['name'] ?? widget.station?.name ?? '주유소';
    final address = d?['NEW_ADR'] ?? d?['address'] ?? widget.station?.address ?? '';
    final brand = (d?['brand'] ?? d?['POLL_DIV_CD'] ?? d?['POLL_DIV_CO'] ?? widget.station?.brand ?? '').toString();
    final result = FavoriteService.toggle(
      id: widget.stationId, type: 'gas', name: name, subtitle: address,
      extra: brand.isNotEmpty ? {'brand': brand} : null,
    );
    setState(() => _isFavorite = result);
    ref.read(favoritesProvider.notifier).refresh();
    WidgetService.updateGasWidget();
  }

  void _openAlertSheet() {
    final name = _detail?['OS_NM'] ?? widget.station?.name ?? '주유소';
    final availableFuels = (_detail?['availableFuelTypes'] as List?)?.cast<String>();
    showFuelTypeAlertSheet(
      context,
      stationId: widget.stationId,
      stationName: name,
      availableFuels: availableFuels,
    );
  }

  void _onScroll() {
    double nearestDelta = double.infinity;
    int nearestIdx = _activeTab;
    for (int i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final offset = box.localToGlobal(Offset.zero).dy;
      final delta = (offset - 180).abs();
      if (offset < 300 && delta < nearestDelta) {
        nearestDelta = delta;
        nearestIdx = i;
      }
    }
    if (nearestIdx != _activeTab) setState(() => _activeTab = nearestIdx);
  }

  Future<void> _scrollToSection(int idx) async {
    setState(() => _activeTab = idx);
    final ctx = _sectionKeys[idx].currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  Map<String, double> get _prices {
    final raw = _detail?['prices'] as Map<String, dynamic>?;
    if (raw == null) {
      // 목록에서 넘어온 단일 가격으로 폴백
      final s = widget.station;
      if (s?.price != null && s?.fuelType != null) {
        return {s!.fuelType: s.price!.toDouble()};
      }
      return {};
    }
    final out = <String, double>{};
    for (final code in _fuelOrder) {
      final v = raw[code];
      if (v != null) out[code] = (v as num).toDouble();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gasBlue));
    }
    if (_detail == null) {
      return const Center(child: Text('정보를 불러올 수 없습니다'));
    }

    final d = _detail!;
    final name = (d['OS_NM'] ?? d['name'] ?? widget.station?.name ?? '주유소').toString();
    final brand = (widget.station?.brand ?? d['brand'] ?? '').toString();
    final prices = _prices;

    // 화면 배경 — HTML #F5F6F8 톤. 카드는 흰색.
    return Container(
      color: isDark ? const Color(0xFF0B0F14) : _kBg,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          if (widget.sheetMode) SliverToBoxAdapter(child: _dragHandle(isDark)),
          SliverToBoxAdapter(child: _headerCard(name, brand, d, isDark)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _GasTabsDelegate(
              labels: _tabLabels,
              activeIndex: _activeTab,
              onTap: _scrollToSection,
              isDark: isDark,
            ),
          ),
          SliverToBoxAdapter(child: _priceCard(prices, d, isDark)),
          SliverToBoxAdapter(child: _graphCard(isDark)),
          SliverToBoxAdapter(child: _stationSection(d, isDark)),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ),
        ],
      ),
    );
  }

  Widget _dragHandle(bool isDark) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isDark ? Colors.white24 : Colors.black26,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _headerCard(String name, String brand, Map<String, dynamic> d, bool isDark) {
    final isSelf    = d['SELF_DIV_CD'] == 'Y' || d['isSelf'] == true;
    final hasCarWash = d['CAR_WASH_YN'] == 'Y' || d['hasCarWash'] == true;
    final distanceText = widget.station?.distanceText ?? '';
    final address   = (d['NEW_ADR'] ?? d['address'] ?? widget.station?.address ?? '').toString();
    final lat = (d['lat'] ?? d['GIS_Y_COOR'])?.toDouble() ?? widget.station?.lat ?? 0.0;
    final lng = (d['lng'] ?? d['GIS_X_COOR'])?.toDouble() ?? widget.station?.lng ?? 0.0;

    // 사용자 요청 — 액션 버튼은 앱 기존 주유 파랑톤 (들어갈 때마다 색 바뀌는 일관성 깨짐 해소).
    const actionColor = AppColors.gasBlue;
    final brandColor = _brandColor(brand);

    final cardBg     = isDark ? const Color(0xFF151B22) : _kCard;
    final titleColor = isDark ? Colors.white : _kInk;
    final subColor   = isDark ? AppColors.darkTextMuted : _kMuted;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12, offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1) 브랜드 아이콘 + 브랜드명 + 셀프/세차 칩
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _brandIcon(brand, brandColor, isDark, widget.station?.name),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.station?.brandName ?? brand,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : _kInk2,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelf) _topChip('셀프', isPrimary: true, isDark: isDark),
              if (isSelf && hasCarWash) const SizedBox(width: 6),
              if (hasCarWash) _topChip('세차', isPrimary: false, isDark: isDark),
            ],
          ),
          const SizedBox(height: 14),
          // 2) 이름 + 편집 버튼 + 별칭
          Builder(builder: (_) {
            final alias = StationAliasService.getGas(widget.stationId);
            final displayName = alias ?? name;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800,
                          letterSpacing: -0.7, height: 1.15,
                          color: titleColor,
                        ),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _editAlias(widget.stationId, name),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          alias != null ? Icons.edit_rounded : Icons.edit_outlined,
                          size: 18,
                          color: alias != null ? actionColor : _kMute2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (alias != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: TextStyle(fontSize: 12, color: _kMute2),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: 10),
          // 3) 주소 + 복사 + 거리 (HTML 양식 — 거리는 빨강)
          InkWell(
            onTap: address.isNotEmpty ? () => _copyAddress(address) : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                if (address.isNotEmpty) ...[
                  Flexible(
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : _kInk2, height: 1.35,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy_rounded, size: 12, color: subColor.withValues(alpha: 0.6)),
                ],
                if (distanceText.isNotEmpty) ...[
                  const Spacer(),
                  const Icon(Icons.location_on_rounded, size: 13, color: _kRed),
                  const SizedBox(width: 3),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _kRed, letterSpacing: -0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 4) 액션 row — 알림 / 즐겨찾기 / 길안내 (모두 앱 기존 파랑톤)
          Row(
            children: [
              _ActionIconBtn(
                icon: _isAlarm
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: _isAlarm ? actionColor : null,
                onTap: _openAlertSheet,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ActionIconBtn(
                icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? actionColor : null,
                onTap: _toggleFavorite,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [actionColor, AppColors.gasBlueDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: actionColor.withValues(alpha: 0.28),
                        blurRadius: 14, offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () =>
                          showNavigationSheet(context, lat: lat, lng: lng, name: name),
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.navigation_rounded, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            distanceText.isNotEmpty
                                ? '길 안내 시작 · $distanceText'
                                : '길 안내 시작',
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topChip(String label, {required bool isPrimary, required bool isDark}) {
    final fg = isPrimary ? _kFuelRegular : _kMuted;
    final bg = isPrimary ? const Color(0xFFEFF6FF) : _kLineSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Future<void> _copyAddress(String addr) async {
    await Clipboard.setData(ClipboardData(text: addr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('주소를 복사했어요'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(40, 0, 40, 80),
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // 브랜드 로고 이미지 (상세화면 hero용 46x46).
  // 휴게소면 EX 로고, 5대 정유사면 진짜 심볼, 그 외는 컬러 텍스트 타일.
  Widget _brandIcon(String brand, Color color, bool isDark, String? stationName) {
    final realLogo = BrandLogo.resolveLogoAsset(brand: brand, stationName: stationName);
    if (realLogo != null) {
      final isSvg = realLogo.toLowerCase().endsWith('.svg');
      return Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isDark ? const Color(0xFF2A3040) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(7),
        child: isSvg
            ? SvgPicture.asset(realLogo, fit: BoxFit.contain)
            : Image.asset(realLogo, fit: BoxFit.contain),
      );
    }
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        _brandShortLabel(brand),
        style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w900,
          color: isDark ? color : _brandColorDark(brand),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  static Color _brandColor(String brand) {
    switch (brand) {
      case 'SKE': return const Color(0xFFFF6600);   // SK 주황
      case 'GSC': return const Color(0xFF00A651);   // GS 초록
      case 'HDO': return const Color(0xFF003DA5);   // 현대 파랑
      case 'SOL': return const Color(0xFFE31E25);   // S-OIL 빨강
      case 'RTO': case 'RTX': return const Color(0xFF6D28D9); // 알뜰 보라
      case 'NHO': return const Color(0xFF16A34A);   // NH 초록
      default:    return AppColors.gasBlue;
    }
  }

  static Color _brandColorDark(String brand) {
    switch (brand) {
      case 'SKE': return const Color(0xFFCC5200);
      case 'GSC': return const Color(0xFF007A3D);
      case 'HDO': return const Color(0xFF002E80);
      case 'SOL': return const Color(0xFFB71418);
      case 'RTO': case 'RTX': return const Color(0xFF5B21B6);
      case 'NHO': return const Color(0xFF15803D);
      default:    return AppColors.gasBlueDark;
    }
  }

  static String _brandShortLabel(String brand) {
    switch (brand) {
      case 'SKE': return 'SK';
      case 'GSC': return 'GS';
      case 'HDO': return 'HD';
      case 'SOL': return 'S-OIL';
      case 'RTO': case 'RTX': return '알뜰';
      case 'NHO': return 'NH';
      default:    return brand.isNotEmpty ? brand.substring(0, brand.length.clamp(0, 3)) : '주유';
    }
  }

  // ─── 가격 카드 (HTML price-card 양식 + 어제 대비 + today chips) ───
  Widget _priceCard(Map<String, double> prices, Map<String, dynamic> d, bool isDark) {
    final cardBg = isDark ? const Color(0xFF151B22) : _kCard;
    // 어제 대비 delta — 서버 응답: { B027: -12, D047: +5, ... }. 누락된 유종은 null.
    final deltaMap = (d['price_delta_vs_yesterday'] is Map)
        ? Map<String, dynamic>.from(d['price_delta_vs_yesterday'] as Map) : <String, dynamic>{};
    // 지역 평균 + 지역 대비 + 최저가 순위 — 모두 휘발유(B027) 기준 노출.
    final regionAvg = (d['region_avg'] is Map)
        ? Map<String, dynamic>.from(d['region_avg'] as Map) : <String, dynamic>{};
    final vsRegion = (d['vs_region_won'] is Map)
        ? Map<String, dynamic>.from(d['vs_region_won'] as Map) : <String, dynamic>{};
    final rank = (d['region_rank'] is Map)
        ? Map<String, dynamic>.from(d['region_rank'] as Map) : null;

    final priceEntries = _fuelOrder
        .where((k) => prices.containsKey(k))
        .map((k) => MapEntry(k, prices[k]!))
        .toList();

    return Container(
      key: _kPrice,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더 — "오늘 주유 가격 · 단위 원/L · 어제 대비"
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('오늘 주유 가격',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : _kInk)),
              const SizedBox(width: 8),
              Text('${_fuelLabelByCode[_userFuelCode] ?? '휘발유'} 기준 · 어제 대비',
                  style: const TextStyle(fontSize: 11, color: _kMute2, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          if (priceEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('가격 정보가 없어요',
                  style: TextStyle(fontSize: 13, color: _kMuted)),
            )
          else
            ...priceEntries.asMap().entries.map((e) {
              final code = e.value.key;
              final price = e.value.value;
              final delta = deltaMap[code];
              return _priceRow(
                code: code,
                price: price,
                delta: delta is num ? delta.toInt() : null,
                isLast: e.key == priceEntries.length - 1,
                isDark: isDark,
              );
            }),
          const SizedBox(height: 14),
          // today chips — 사용자 등록 유종 기준. server 가 region_rank 도 동일 유종으로 계산.
          Row(
            children: [
              _todayChip(
                label: '지역 평균',
                value: _regionAvgText(regionAvg, _userFuelCode),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _todayChip(
                label: '지역 대비',
                value: _vsRegionText(vsRegion, _userFuelCode),
                tone: _vsRegionTone(vsRegion, _userFuelCode),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _todayChip(
                label: '최저가 순위',
                value: _rankText(rank),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 어제 대비 delta chip + 큰 가격
  Widget _priceRow({
    required String code, required double price, required int? delta,
    required bool isLast, required bool isDark,
  }) {
    final label = _fuelLabel[code] ?? code;
    final fuelColor = _fuelColor(code);
    final fuelBg = _fuelBg(code);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      decoration: BoxDecoration(
        border: isLast ? null : Border(
          bottom: BorderSide(color: isDark ? Colors.white12 : _kLineSoft),
        ),
      ),
      child: Row(
        children: [
          // 유종 chip (좌측 80px)
          SizedBox(
            width: 96,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: fuelBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(color: fuelColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: fuelColor.computeLuminance() > 0.5
                            ? fuelColor.withValues(alpha: 0.8)
                            : fuelColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // delta chip
          Expanded(child: _deltaChip(delta, isDark)),
          const SizedBox(width: 6),
          // 가격
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: _formatPrice(price),
                  style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.7,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDark ? Colors.white : _kInk,
                  ),
                ),
                const TextSpan(
                  text: '원',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaChip(int? delta, bool isDark) {
    if (delta == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _kLineSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('─', style: TextStyle(fontSize: 11, color: _kMuted, fontWeight: FontWeight.w700)),
        ),
      );
    }
    final isUp = delta > 0;
    final isZero = delta == 0;
    final bg = isZero ? _kLineSoft : (isUp ? _kRedBg : _kGreenBg);
    final fg = isZero ? _kMuted : (isUp ? _kRed : _kGreen);
    final arrow = isZero ? null : (isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (arrow != null) Icon(arrow, size: 14, color: fg),
            Text(
              isZero ? '0원' : '${delta.abs()}원',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayChip({required String label, required String value, _ChipTone? tone, required bool isDark}) {
    final valColor = tone == _ChipTone.up ? _kRed
                   : tone == _ChipTone.down ? _kGreen
                   : (isDark ? Colors.white : _kInk);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : _kLineSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10, color: _kMuted, fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                letterSpacing: -0.3, color: valColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _regionAvgText(Map<String, dynamic> regionAvg, String code) {
    final v = regionAvg[code];
    if (v is num && v > 0) return '${_formatPrice(v.toDouble())}원';
    return '─';
  }

  String _vsRegionText(Map<String, dynamic> vsRegion, String code) {
    final v = vsRegion[code];
    if (v is num) {
      if (v == 0) return '동일';
      return v < 0 ? '${v.abs().round()}원 저렴' : '${v.round()}원 비쌈';
    }
    return '─';
  }

  _ChipTone? _vsRegionTone(Map<String, dynamic> vsRegion, String code) {
    final v = vsRegion[code];
    if (v is num) {
      if (v < 0) return _ChipTone.down;
      if (v > 0) return _ChipTone.up;
    }
    return null;
  }

  String _rankText(Map<String, dynamic>? rank) {
    if (rank == null) return '─';
    final r = rank['rank'];
    final t = rank['total'];
    if (r is num && t is num && t > 0) return '${r.toInt()}위 / ${t.toInt()}곳';
    return '─';
  }

  // ─── 가격 추이 카드 (fl_chart 멀티라인) ─────────────────────────────────
  Widget _graphCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF151B22) : _kCard;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 타이틀 + 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('가격 추이',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : _kInk)),
              Wrap(
                spacing: 10,
                children: [
                  _legend('휘발유', _kFuelRegular),
                  _legend('고급', _kFuelPremium),
                  _legend('경유', _kFuelDiesel),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 기간 세그먼트
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : _kLineSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _segBtn('1주', '1w', isDark),
                _segBtn('4주', '4w', isDark),
                _segBtn('3개월', '3m', isDark),
                _segBtn('1년', '1y', isDark),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: _chartLoading
                ? const Center(child: CircularProgressIndicator(
                    color: _kFuelRegular, strokeWidth: 2))
                : _buildChart(isDark),
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: _kInk2)),
      ],
    );
  }

  Widget _segBtn(String label, String value, bool isDark) {
    final active = _chartPeriod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _loadChart(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? (isDark ? const Color(0xFF1E2530) : _kCard) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active && !isDark ? [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 2, offset: const Offset(0, 1)),
            ] : null,
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: active
                ? (isDark ? Colors.white : _kInk)
                : _kMuted,
          )),
        ),
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    final raw = _chartData;
    if (raw == null) {
      return const Center(child: Text('가격 추이가 없어요', style: TextStyle(color: _kMute2)));
    }
    final points = (raw['points'] as List?) ?? const [];
    if (points.isEmpty) {
      return const Center(child: Text('가격 추이 데이터 없음', style: TextStyle(color: _kMute2)));
    }
    final fuels = ((raw['fuels'] as List?) ?? const ['B027']).cast<String>();

    // 시리즈 만들기 — fuel 별 line
    final seriesPoints = <String, List<FlSpot>>{};
    for (final f in fuels) seriesPoints[f] = [];
    double? minY, maxY;
    for (int i = 0; i < points.length; i++) {
      final p = points[i] as Map;
      final priceMap = (p['prices'] is Map) ? p['prices'] as Map : const {};
      for (final f in fuels) {
        final v = priceMap[f];
        if (v is num) {
          final y = v.toDouble();
          seriesPoints[f]!.add(FlSpot(i.toDouble(), y));
          if (minY == null || y < minY) minY = y;
          if (maxY == null || y > maxY) maxY = y;
        }
      }
    }
    if (minY == null || maxY == null) {
      return const Center(child: Text('가격 추이 데이터 없음', style: TextStyle(color: _kMute2)));
    }
    // y 축 여유 — 가격 변동이 작은 케이스도 시각화 가능하게 padding
    final ySpan = (maxY - minY).abs();
    final pad = (ySpan == 0) ? 100.0 : ySpan * 0.15;
    final yMin = (minY - pad).floorToDouble();
    final yMax = (maxY + pad).ceilToDouble();

    final lineBars = <LineChartBarData>[];
    for (final f in fuels) {
      final pts = seriesPoints[f]!;
      if (pts.isEmpty) continue;
      lineBars.add(LineChartBarData(
        spots: pts,
        isCurved: false,
        color: _fuelColor(f),
        barWidth: f == 'B027' ? 2.4 : 2.0,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: f == 'B034', // 고급은 영역 살짝 칠하기
          color: _kFuelPremium.withValues(alpha: 0.06),
        ),
      ));
    }

    // x 라벨 (4-5개 분포)
    final xLabels = <int, String>{};
    if (points.length >= 2) {
      const targets = 4;
      final step = (points.length / targets).ceil().clamp(1, points.length);
      for (int i = 0; i < points.length; i += step) {
        final p = points[i] as Map;
        final date = (p['date'] ?? '').toString();
        if (date.length >= 8) {
          xLabels[i] = '${int.parse(date.substring(4,6))}/${int.parse(date.substring(6,8))}';
        }
      }
      // 마지막은 항상 "오늘"
      xLabels[points.length - 1] = '오늘';
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: yMin,
        maxY: yMax,
        // y interval — 라벨 4-5개 분포로 강제. (yMax-yMin)/4 가 너무 작으면 라벨이 위아래로 겹침.
        // 100원 단위 floor 로 정렬해서 깔끔한 숫자(2200/2300/...).
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _niceYInterval(yMax - yMin),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: _kLine, strokeWidth: 1, dashArray: [2, 4]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: _niceYInterval(yMax - yMin),
              getTitlesWidget: (v, meta) {
                // 최상단/최하단 라벨은 그리지 않음 (border 와 겹쳐서 잘리는 시각 문제).
                if (v <= yMin + 0.5 || v >= yMax - 0.5) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _formatPrice(v),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: _kMute2, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                final label = xLabels[i];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label,
                      style: const TextStyle(fontSize: 9, color: _kMute2, fontWeight: FontWeight.w600)),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: lineBars,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => isDark ? const Color(0xFF1E2530) : _kInk,
            getTooltipItems: (spots) => spots.map((s) {
              final fuelIdx = lineBars.indexOf(s.bar);
              final fuelCode = fuelIdx >= 0 && fuelIdx < fuels.length ? fuels[fuelIdx] : '';
              final label = _fuelLabel[fuelCode] ?? fuelCode;
              return LineTooltipItem(
                '$label  ${_formatPrice(s.y)}원',
                TextStyle(color: _fuelColor(fuelCode), fontSize: 11, fontWeight: FontWeight.w700),
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  // ─── 주유소 정보 카드 (HTML info-card 양식) ─────────────────────────────
  Widget _stationSection(Map<String, dynamic> d, bool isDark) {
    final address = (d['NEW_ADR'] ?? d['address'] ?? '').toString();
    final isSel24 = d['isSel24'] == true || d['SEL24_YN'] == 'Y';
    final openTime = isSel24 ? '24시간 영업' : (d['openTime']?.toString() ?? '정보 없음');
    final isSelf = d['SELF_DIV_CD'] == 'Y' || d['isSelf'] == true;
    final hasCarWash = d['CAR_WASH_YN'] == 'Y' || d['hasCarWash'] == true;
    final hasCvs = d['hasCvs'] == true || d['CVS_YN'] == 'Y';
    final phone = (d['TEL'] ?? d['phone'] ?? '').toString();
    final cardBg = isDark ? const Color(0xFF151B22) : _kCard;

    return Container(
      key: _kStation,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주유소 정보',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : _kInk)),
          const SizedBox(height: 8),
          if (address.isNotEmpty) _infoRow('주소', address, isDark),
          _infoRow('영업시간', openTime, isDark,
              valueColor: isSel24 ? _kGreen : (openTime == '정보 없음' ? _kMute2 : null)),
          _infoRow('셀프', isSelf ? '가능' : '불가', isDark,
              valueColor: isSelf ? _kGreen : null),
          _infoRow('세차', hasCarWash ? '가능' : '불가', isDark,
              valueColor: hasCarWash ? _kGreen : null),
          if (hasCvs) _infoRow('편의점', '있음', isDark, valueColor: _kGreen),
          if (phone.isNotEmpty)
            InkWell(
              onTap: () => launchUrl(Uri.parse('tel:$phone')),
              child: _infoRow('전화', phone, isDark, valueColor: AppColors.gasBlue, isLast: true),
            )
          else
            _infoRow('전화', '─', isDark, valueColor: _kMute2, isLast: true),
        ],
      ),
    );
  }

  // ─── 공용 소형 위젯 ───
  Widget _infoRow(String label, String value, bool isDark,
      {Color? valueColor, bool isLast = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        decoration: BoxDecoration(
          border: isLast ? null : Border(
            bottom: BorderSide(color: isDark ? Colors.white12 : _kLineSoft),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: valueColor ?? (isDark ? Colors.white : _kInk))),
            ),
          ],
        ),
      );

  String _formatPrice(double price) => price.toInt().toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  // y축 간격을 깔끔한 100/200/500/1000 단위로. 라벨 4-5개 분포 + 겹침 방지.
  double _niceYInterval(double span) {
    if (span <= 0) return 100;
    final rough = span / 4;
    if (rough <= 50) return 50;
    if (rough <= 100) return 100;
    if (rough <= 200) return 200;
    if (rough <= 500) return 500;
    return 1000;
  }
}

// ─── 액션 아이콘 버튼 ───
class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool loading;
  final VoidCallback onTap;
  final bool isDark;
  const _ActionIconBtn({
    required this.icon, this.color, this.loading = false,
    required this.onTap, required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkCard : const Color(0xFFF1F5F9);
    final border = isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0);
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 0.6),
        ),
        child: loading
            ? const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gasBlue)))
            : Icon(icon, size: 22,
                color: color ?? (isDark ? Colors.white70 : Colors.black54)),
      ),
    );
  }
}

// ─── 섹션 탭 pinned 헤더 ───
class _GasTabsDelegate extends SliverPersistentHeaderDelegate {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onTap;
  final bool isDark;
  _GasTabsDelegate({required this.labels, required this.activeIndex,
      required this.onTap, required this.isDark});

  @override double get minExtent => 48;
  @override double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? AppColors.darkBg : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == activeIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? AppColors.gasBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                    )),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _GasTabsDelegate old) =>
      old.activeIndex != activeIndex || old.isDark != isDark;
}
