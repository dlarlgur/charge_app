import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/alert_service.dart';
import '../favorites/favorites_screen.dart';
import '../widgets/shared_widgets.dart' show showFuelTypeAlertSheet, BrandLogo;

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

  static const List<String> _tabLabels = ['요금', '주유소'];
  List<GlobalKey> get _sectionKeys => [_kPrice, _kStation];

  static const List<String> _fuelOrder = ['B027', 'B034', 'D047', 'K015'];
  static const Map<String, String> _fuelLabel = {
    'B027': '휘발유', 'B034': '고급휘발유', 'D047': '경유', 'K015': 'LPG',
  };

  // 유종별 색상
  static Color _fuelColor(String code) {
    switch (code) {
      case 'B027': return const Color(0xFF2563EB); // 휘발유 — 파랑
      case 'B034': return const Color(0xFFD97706); // 고급휘발유 — 금색
      case 'D047': return const Color(0xFF16A34A); // 경유 — 초록
      case 'K015': return const Color(0xFF7C3AED); // LPG — 보라
      default:     return AppColors.gasBlue;
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

  Future<void> _loadDetail() async {
    try {
      final data = await ApiService().getGasStationDetail(widget.stationId);
      if (mounted) setState(() { _detail = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleFavorite() {
    final d = _detail;
    final name = d?['OS_NM'] ?? d?['name'] ?? widget.station?.name ?? '주유소';
    final address = d?['NEW_ADR'] ?? d?['address'] ?? widget.station?.address ?? '';
    final result = FavoriteService.toggle(
      id: widget.stationId, type: 'gas', name: name, subtitle: address,
    );
    setState(() => _isFavorite = result);
    ref.read(favoritesProvider.notifier).refresh();
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

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (widget.sheetMode) SliverToBoxAdapter(child: _dragHandle(isDark)),
        SliverToBoxAdapter(child: _heroCard(name, brand, prices, d, isDark)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _GasTabsDelegate(
            labels: _tabLabels,
            activeIndex: _activeTab,
            onTap: _scrollToSection,
            isDark: isDark,
          ),
        ),
        SliverToBoxAdapter(child: _priceSection(prices, isDark)),
        SliverToBoxAdapter(child: _stationSection(d, isDark)),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ),
      ],
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

  Widget _heroCard(String name, String brand, Map<String, double> prices,
      Map<String, dynamic> d, bool isDark) {
    final isSelf    = d['SELF_DIV_CD'] == 'Y' || d['isSelf'] == true;
    final hasCarWash = d['CAR_WASH_YN'] == 'Y' || d['hasCarWash'] == true;
    final distanceText = widget.station?.distanceText ?? '';
    final address   = (d['NEW_ADR'] ?? d['address'] ?? widget.station?.address ?? '').toString();
    final lat = (d['lat'] ?? d['GIS_Y_COOR'])?.toDouble() ?? widget.station?.lat ?? 0.0;
    final lng = (d['lng'] ?? d['GIS_X_COOR'])?.toDouble() ?? widget.station?.lng ?? 0.0;

    // 브랜드별 대표색
    final brandColor = _brandColor(brand);

    // 가격 행: 있는 유종만 순서대로
    final priceEntries = _fuelOrder
        .where((k) => prices.containsKey(k))
        .map((k) => MapEntry(k, prices[k]!))
        .toList();

    final cardBg    = isDark ? const Color(0xFF151B22) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor  = isDark ? AppColors.darkTextMuted : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFECEFF3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 20, spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1) 브랜드 아이콘 + 브랜드명 + 셀프/세차 (우상단)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _brandIcon(brand, brandColor, isDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.station?.brandName ?? brand,
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: subColor, letterSpacing: -0.2,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelf || hasCarWash) ...[
                  if (isSelf)
                    _topTag('셀프', AppColors.gasBlue),
                  if (isSelf && hasCarWash) const SizedBox(width: 6),
                  if (hasCarWash)
                    _topTag('세차', AppColors.success),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // 2) 이름
            Text(
              name,
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
                letterSpacing: -0.6, height: 1.22,
                color: titleColor,
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            // 3) 주소 + 복사 + 거리
            InkWell(
              onTap: address.isNotEmpty ? () => _copyAddress(address) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  if (address.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500,
                          color: subColor, height: 1.35,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded,
                        size: 13, color: subColor.withValues(alpha: 0.6)),
                  ],
                  if (distanceText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.near_me_rounded, size: 13, color: brandColor),
                    const SizedBox(width: 3),
                    Text(
                      distanceText,
                      style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: brandColor, letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFEEF1F5),
            ),
            const SizedBox(height: 12),
            // 4) 유종별 가격 행
            if (priceEntries.isEmpty)
              Text('가격 정보 없음',
                  style: TextStyle(fontSize: 14, color: subColor))
            else
              ...priceEntries.asMap().entries.map((e) {
                final isMain = e.key == 0;
                final fuelCode = e.value.key;
                final label = _fuelLabel[fuelCode] ?? fuelCode;
                final price = e.value.value;
                final fuelColor = _fuelColor(fuelCode);
                return Padding(
                  padding: EdgeInsets.only(bottom: isMain ? 6 : 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: fuelColor.withValues(alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? fuelColor
                                : fuelColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatPrice(price),
                        style: TextStyle(
                          fontSize: isMain ? 26 : 18,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: isDark
                              ? fuelColor
                              : fuelColor.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        '원',
                        style: TextStyle(
                          fontSize: isMain ? 14 : 12,
                          fontWeight: FontWeight.w700,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFEEF1F5),
            ),
            const SizedBox(height: 10),
            // 5) 액션: 알림 + 즐겨찾기 + 길 안내 시작
            Row(
              children: [
                _ActionIconBtn(
                  icon: _isAlarm
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: _isAlarm ? brandColor : null,
                  onTap: _openAlertSheet,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _ActionIconBtn(
                  icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? brandColor : null,
                  onTap: _toggleFavorite,
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        showNavigationSheet(context, lat: lat, lng: lng, name: name),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: Text(
                      distanceText.isNotEmpty
                          ? '길 안내 시작 ($distanceText)'
                          : '길 안내 시작',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  // 브랜드 로고 이미지 (BrandLogo 위젯 재사용, 상세화면용 46x46)
  Widget _brandIcon(String brand, Color color, bool isDark) {
    return SizedBox(
      width: 46,
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          'assets/brands/${BrandLogo.assetName(brand)}.png',
          width: 46, height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
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
          ),
        ),
      ),
    );
  }

  Widget _topTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w800,
          color: color, letterSpacing: -0.2,
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

  // ─── 섹션: 요금 ───
  Widget _priceSection(Map<String, double> prices, bool isDark) {
    return Container(
      key: _kPrice,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('요금', '단위 원/L', isDark),
          const SizedBox(height: 12),
          if (prices.isEmpty)
            _noticeBox('가격 정보가 없어요', isDark)
          else
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
                  width: 0.6,
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < prices.length; i++) ...[
                    if (i > 0) _divider(isDark),
                    _priceRow(prices.keys.elementAt(i), prices.values.elementAt(i), isDark),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _priceRow(String code, double price, bool isDark) {
    final label = _fuelLabel[code] ?? code;
    final isMain = code == (widget.station?.fuelType ?? 'B027');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gasBlue.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark)),
          ),
          const Spacer(),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: _formatPrice(price),
                  style: TextStyle(
                    fontSize: isMain ? 22 : 18,
                    fontWeight: FontWeight.w800, letterSpacing: -0.4,
                    color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark,
                  ),
                ),
                TextSpan(
                  text: '원',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 섹션: 주유소 정보 ───
  Widget _stationSection(Map<String, dynamic> d, bool isDark) {
    final address = (d['NEW_ADR'] ?? d['address'] ?? '').toString();
    final openTime = (d['openTime'] ?? '정보 없음').toString();
    final isSelf = d['SELF_DIV_CD'] == 'Y' || d['isSelf'] == true;
    final hasCarWash = d['CAR_WASH_YN'] == 'Y' || d['hasCarWash'] == true;
    final phone = (d['TEL'] ?? d['phone'] ?? '').toString();

    return Container(
      key: _kStation,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('주유소', null, isDark),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
                width: 0.6,
              ),
            ),
            child: Column(
              children: [
                if (address.isNotEmpty) ...[_infoRow('주소', address, isDark), _divider(isDark)],
                _infoRow('영업시간', openTime, isDark),
                _divider(isDark),
                _infoRow('셀프', isSelf ? '가능' : '불가', isDark,
                    valueColor: isSelf ? AppColors.success : null),
                _divider(isDark),
                _infoRow('세차', hasCarWash ? '가능' : '불가', isDark,
                    valueColor: hasCarWash ? AppColors.success : null),
                if (phone.isNotEmpty) ...[
                  _divider(isDark),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('tel:$phone')),
                    child: _infoRow('전화', phone, isDark, valueColor: AppColors.gasBlue),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 공용 소형 위젯 ───
  Widget _sectionTitle(String title, String? trailing, bool isDark) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3,
                  color: isDark ? Colors.white : Colors.black87)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(trailing,
                  style: TextStyle(fontSize: 12,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            ),
          ],
        ],
      );

  Widget _noticeBox(String text, bool isDark) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
      );

  Widget _infoRow(String label, String value, bool isDark, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                      color: valueColor ?? (isDark ? Colors.white : Colors.black87))),
            ),
          ],
        ),
      );

  Widget _divider(bool isDark) => Divider(
        height: 1, thickness: 0.5,
        color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder);

  String _formatPrice(double price) => price.toInt().toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
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
