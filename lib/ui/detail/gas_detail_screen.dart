import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/alert_service.dart';
import '../favorites/favorites_screen.dart';
import '../widgets/shared_widgets.dart' show showFuelTypeAlertSheet;

class GasDetailScreen extends ConsumerStatefulWidget {
  final String stationId;
  final GasStation? station; // 목록에서 넘어온 데이터 (price, brand 포함)
  const GasDetailScreen({super.key, required this.stationId, this.station});
  @override
  ConsumerState<GasDetailScreen> createState() => _GasDetailScreenState();
}

class _GasDetailScreenState extends ConsumerState<GasDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _isFavorite = false;

  bool get _isAlertOn => AlertService().isSubscribed(widget.stationId);

  @override
  void initState() {
    super.initState();
    _isFavorite = FavoriteService.isFavorite(widget.stationId, 'gas');
    AlertService().subsChanged.addListener(_onSubsChanged);
    _loadDetail();
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_onSubsChanged);
    super.dispose();
  }

  void _onSubsChanged() => setState(() {});

  Future<void> _loadDetail() async {
    try {
      final data = await ApiService().getGasStationDetail(widget.stationId);
      if (mounted) setState(() { _detail = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('주유소 상세'),
        actions: [
          IconButton(
            icon: Icon(
              _isAlertOn ? Icons.notifications_rounded : Icons.notifications_none_rounded,
              color: _isAlertOn ? AppColors.gasBlue : null,
            ),
            onPressed: () {
              final name = _detail?['OS_NM'] ?? widget.station?.name ?? '주유소';
              final availableFuels = (_detail?['availableFuelTypes'] as List?)?.cast<String>();
              showFuelTypeAlertSheet(
                context,
                stationId: widget.stationId,
                stationName: name,
                availableFuels: availableFuels,
              );
            },
          ),
          IconButton(
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? AppColors.gasBlue : null),
            onPressed: () {
              final d = _detail;
              final name = d?['OS_NM'] ?? d?['name'] ?? widget.station?.name ?? '주유소';
              final address = d?['NEW_ADR'] ?? d?['address'] ?? widget.station?.address ?? '';
              final result = FavoriteService.toggle(
                id: widget.stationId, type: 'gas', name: name, subtitle: address,
              );
              setState(() => _isFavorite = result);
              ref.read(favoritesProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('정보를 불러올 수 없습니다'))
              : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    final d = _detail!;
    final name = d['OS_NM'] ?? d['name'] ?? '주유소';
    final brand = widget.station?.brand ?? d['brand'] ?? '';
    final address = d['NEW_ADR'] ?? d['address'] ?? '';
    final phone = d['TEL'] ?? d['phone'] ?? '';
    final isSelf = d['SELF_DIV_CD'] == 'Y' || d['isSelf'] == true;
    final hasCarWash = d['CAR_WASH_YN'] == 'Y' || d['hasCarWash'] == true;
    final distanceText = widget.station?.distanceText ?? d['distanceText'] ?? '';
    
    // 서버에서 받은 모든 유종 가격
    final pricesRaw = d['prices'] as Map<String, dynamic>?;
    final availableFuels = (d['availableFuelTypes'] as List?)?.cast<String>() ?? [];
    
    // 유종 순서대로 정렬 (휘발유 → 고급휘발유 → 경유 → LPG)
    const fuelOrder = ['B027', 'B034', 'D047', 'K015'];
    final prices = <String, double>{};
    if (pricesRaw != null) {
      for (final code in fuelOrder) {
        if (pricesRaw.containsKey(code)) {
          final priceValue = pricesRaw[code];
          if (priceValue != null) {
            prices[code] = (priceValue as num).toDouble();
          }
        }
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 히어로 카드 (화면 전체 너비)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B26) : const Color(0xFFF8FAFC),
              border: isDark ? null : Border(
                bottom: BorderSide(color: AppColors.lightCardBorder, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (brand.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1F3B82F6) : const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(brand, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.gasBlue)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                // 모든 유종 가격 표시
                if (prices.isNotEmpty)
                  ...prices.entries.map((entry) {
                    final fuelLabel = _getFuelLabel(entry.key);
                    final priceText = '${entry.value.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원/L';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x1F3B82F6) : const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(fuelLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark)),
                          ),
                          Text(
                            priceText,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isDark ? AppColors.gasBlue : AppColors.gasBlueDark, letterSpacing: -0.5),
                          ),
                        ],
                      ),
                    );
                  }).toList()
                else
                  Text(
                    '가격 정보 없음',
                    style: TextStyle(fontSize: 16, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                  ),
              ],
            ),
          ),
          // 정보 섹션
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _infoRow('주소', address),
                _infoRow('영업시간', d['openTime'] ?? '정보 없음'),
                _infoRow('셀프', isSelf ? '가능' : '불가', valueColor: isSelf ? AppColors.success : null),
                _infoRow('세차', hasCarWash ? '가능' : '불가', valueColor: hasCarWash ? AppColors.success : null),
                _infoRow('거리', distanceText),
                const SizedBox(height: 20),
                // 액션 버튼
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openNavigation(d),
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('길찾기'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _callPhone(phone),
                        icon: const Icon(Icons.phone_rounded, size: 18),
                        label: const Text('전화하기'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getFuelLabel(String fuelType) {
    const labels = {
      'B027': '휘발유',
      'B034': '고급휘발유',
      'D047': '경유',
      'K015': 'LPG',
    };
    return labels[fuelType] ?? '휘발유';
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(child: Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor),
            textAlign: TextAlign.end,
          )),
        ],
      ),
    );
  }

  void _openNavigation(Map<String, dynamic> d) {
    final lat = (d['lat'] ?? d['GIS_Y_COOR'])?.toDouble() ?? 0.0;
    final lng = (d['lng'] ?? d['GIS_X_COOR'])?.toDouble() ?? 0.0;
    final name = d['OS_NM'] ?? d['name'] ?? '';
    showNavigationSheet(context, lat: lat, lng: lng, name: name);
  }

  void _callPhone(String phone) {
    if (phone.isNotEmpty) launchUrl(Uri.parse('tel:$phone'));
  }
}
