import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/navigation_util.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../widgets/shared_widgets.dart';
import '../favorites/favorites_screen.dart';

class EvDetailScreen extends ConsumerStatefulWidget {
  final String stationId;
  final EvStation? station;
  const EvDetailScreen({super.key, required this.stationId, this.station});
  @override
  ConsumerState<EvDetailScreen> createState() => _EvDetailScreenState();
}

class _EvDetailScreenState extends ConsumerState<EvDetailScreen> {
  EvStation? _station;
  bool _loading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = FavoriteService.isFavorite(widget.stationId, 'ev');
    if (widget.station != null) {
      _station = widget.station;
      _loading = false;
    } else {
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await ApiService().getEvStationDetail(widget.stationId);
      if (mounted) setState(() { _station = EvStation.fromJson(detail); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('충전소 상세'),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? AppColors.evGreen : null),
            onPressed: () {
              final s = _station;
              if (s == null) return;
              final result = FavoriteService.toggle(
                id: widget.stationId, type: 'ev', name: s.name, subtitle: s.address,
              );
              setState(() => _isFavorite = result);
              // 즐겨찾기 탭 즉시 갱신
              ref.read(favoritesProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.evGreen))
          : _station == null
              ? const Center(child: Text('정보를 불러올 수 없습니다'))
              : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    final s = _station!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 히어로 카드
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A2E1F) : AppColors.lightEvActiveCard,
              borderRadius: BorderRadius.circular(16),
              border: isDark ? null : Border.all(color: AppColors.lightEvActiveBorder, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EvOperatorLogo(operator: s.operator),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              s.isTesla
                                  ? _badge('${s.totalCount}대', AppColors.evGreen,
                                      isDark ? AppColors.darkBadgeAvailBg : AppColors.lightBadgeAvailBg)
                                  : _badge(s.hasAvailable ? '이용가능' : '이용불가',
                                      s.hasAvailable ? AppColors.statusAvailable : AppColors.statusOffline,
                                      isDark ? AppColors.darkBadgeAvailBg : AppColors.lightBadgeAvailBg),
                              const SizedBox(width: 6),
                              Text(s.operator, style: TextStyle(fontSize: 12,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                              if (s.chargers.any((c) => c.isFast)) ...[
                                const SizedBox(width: 6),
                                _badge('DC 급속', AppColors.statusFast,
                                    isDark ? AppColors.darkBadgeFastBg : AppColors.lightBadgeFastBg),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      s.maxPowerText ?? '',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.evGreen : AppColors.evGreenDark),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 충전 요금 카드
          if (s.hasPriceInfo) ...[
            _buildPriceCard(s, isDark),
            const SizedBox(height: 16),
          ],

          // 충전기 현황 카드
          Row(
            children: [
              Text('충전기 현황', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF60A5FA) : AppColors.gasBlueDark)),
              const SizedBox(width: 6),
              Text('총 ${s.totalCount}대', style: TextStyle(fontSize: 12,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            ],
          ),
          const SizedBox(height: 10),
          if (s.isTesla)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder, width: 0.5),
              ),
              child: Text('실시간 정보 없음',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            )
          else
            Row(
              children: [
                _statusCounter('이용가능', s.availableCount, AppColors.statusAvailable, isDark),
                const SizedBox(width: 8),
                _statusCounter('충전중', s.chargingCount, AppColors.statusCharging, isDark),
                const SizedBox(width: 8),
                _statusCounter('고장', s.offlineCount, AppColors.statusOffline, isDark),
              ],
            ),
          const SizedBox(height: 20),

          // 개별 충전기 목록
          if (s.chargers.isNotEmpty) ...[
            Text('충전기 목록', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF60A5FA) : AppColors.gasBlueDark)),
            const SizedBox(height: 10),
            ...([...s.chargers]..sort((a, b) {
                int order(ChargerStatus s) => switch (s) {
                  ChargerStatus.available => 0,
                  ChargerStatus.charging  => 1,
                  _                       => 2,
                };
                return order(a.status).compareTo(order(b.status));
              })).map((charger) => _chargerTile(charger, isDark)),
            const SizedBox(height: 8),
            Text('충전기 상태는 실시간과 다를 수 있습니다',
              style: TextStyle(fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            const SizedBox(height: 16),
          ],

          // 정보 행
          _infoRow('주소', s.address),
          _infoRow('충전타입', s.chargerTypeText),
          _infoRow('이용시간', s.useTime),
          _infoRow('주차요금', s.parkingFree ? '무료' : '유료',
              valueColor: s.parkingFree ? AppColors.success : null),
          if (s.limitYn || (s.limitDetail?.isNotEmpty == true)) _infoRow(
            '이용제한',
            s.limitDetail?.isNotEmpty == true ? s.limitDetail! : '외부인 이용 제한',
            valueColor: const Color(0xFFE24B4A),
          ),
          if (s.note?.isNotEmpty == true) _infoRow('충전소 안내', s.note!),
          if (s.distanceText.isNotEmpty) _infoRow('거리', s.distanceText),
          const SizedBox(height: 20),

          // 액션 버튼
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => showNavigationSheet(context, lat: s.lat, lng: s.lng, name: s.name),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('길찾기'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.evGreen),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (s.phone != null && s.phone!.isNotEmpty) {
                      launchUrl(Uri.parse('tel:${s.phone}'));
                    }
                  },
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
    );
  }

  Widget _buildPriceCard(EvStation s, bool isDark) {
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;

    Widget priceCol(String label, int? price, Color accent) {
      return Expanded(
        child: Column(
          children: [
            Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: mutedColor)),
            const SizedBox(height: 6),
            price != null
              ? Text('$price원',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent,
                    letterSpacing: -0.3))
              : Text('-', style: TextStyle(fontSize: 16, color: mutedColor, fontWeight: FontWeight.w500)),
            Text('원/kWh',
              style: TextStyle(fontSize: 9, color: mutedColor, fontWeight: FontWeight.w400)),
          ],
        ),
      );
    }

    Widget priceRow(String tier, Color tierColor, int? fast, int? slow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tier, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tierColor)),
              ),
            ),
            const SizedBox(width: 12),
            priceCol('급속', fast, AppColors.statusFast),
            Container(width: 1, height: 36, color: borderColor),
            priceCol('완속', slow, AppColors.evGreen),
          ],
        ),
      );
    }

    final hasMember = s.unitPriceFastMember != null || s.unitPriceSlowMember != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('충전 요금',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF60A5FA) : AppColors.gasBlueDark)),
        const SizedBox(height: 10),
        priceRow('비회원', isDark ? Colors.white60 : Colors.black54,
          s.unitPriceFast, s.unitPriceSlow),
        if (hasMember) ...[
          const SizedBox(height: 8),
          priceRow('회원', AppColors.evGreen,
            s.unitPriceFastMember, s.unitPriceSlowMember),
        ],
      ],
    );
  }

  Widget _badge(String text, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statusCounter(String label, int count, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.08 : 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2), width: 0.5),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chargerTile(Charger charger, bool isDark) {
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    Color statusColor;
    String statusText;
    String? subText;
    Color subTextColor;

    switch (charger.status) {
      case ChargerStatus.available:
        statusColor = AppColors.statusAvailable;
        statusText = '충전가능';
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 마지막 충전'
            : null;
        subTextColor = mutedColor;
        break;
      case ChargerStatus.charging:
        statusColor = AppColors.statusCharging;
        statusText = '충전중';
        final startDt = charger.chargingStarted ?? charger.lastStatusUpdate;
        subText = startDt != null ? _chargingElapsed(startDt) : null;
        subTextColor = AppColors.statusCharging;
        break;
      case ChargerStatus.unknown:
        statusColor = AppColors.statusOffline;
        statusText = '상태확인 불가';
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 고장'
            : null;
        subTextColor = AppColors.statusOffline;
        break;
      default:
        statusColor = AppColors.statusOffline;
        statusText = charger.status.label;
        subText = charger.lastStatusUpdate != null
            ? '${_timeAgo(charger.lastStatusUpdate!)} 고장'
            : null;
        subTextColor = mutedColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
            width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 왼쪽: 상태 + 시간 서브텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
                if (subText != null) ...[
                  const SizedBox(height: 3),
                  Text(subText,
                      style: TextStyle(fontSize: 11, color: subTextColor)),
                ],
              ],
            ),
          ),
          // 오른쪽: 충전기 타입 + 출력
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(charger.typeText,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 2),
              Text('${charger.output}kW',
                  style: TextStyle(fontSize: 11, color: mutedColor)),
            ],
          ),
        ],
      ),
    );
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) {
      final m = diff.inMinutes % 60;
      return m > 0 ? '${diff.inHours}시간 ${m}분 전' : '${diff.inHours}시간 전';
    }
    return '${diff.inDays}일 전';
  }

  String _chargingElapsed(DateTime startDt) {
    final diff = DateTime.now().difference(startDt);
    if (diff.inMinutes < 1) return '방금 시작';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 충전중';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? '$h시간 ${m}분 충전중' : '$h시간 충전중';
  }
}
