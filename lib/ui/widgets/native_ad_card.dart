import 'package:cached_network_image/cached_network_image.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/ad_service.dart';
import '../../data/services/house_ad_service.dart';
import '../../data/services/list_ad_cache.dart';

/// 인-리스트 광고 카드.
///
/// 두 종류:
///  - AdMob 네이티브 광고 (factoryId=stationCardList) — 슬롯 4·8.
///  - House ad (콘솔 등록) — AdMob 슬롯(4·8·12·…·32) bypass 대체 또는 그 외 위치.
///
/// 호출하는 쪽에서 어느 종류인지 결정해서 적합한 위젯을 그림.
class AdMobNativeCard extends StatefulWidget {
  /// AdMob 광고 단위 ID.
  final String adUnitId;
  /// EV 탭 컨텍스트 — 좌측 4dp 컬러 스트립이 있는 layout 사용.
  final bool isEv;
  final EdgeInsets margin;

  const AdMobNativeCard({
    super.key,
    required this.adUnitId,
    this.isEv = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<AdMobNativeCard> createState() => _AdMobNativeCardState();
}

class _AdMobNativeCardState extends State<AdMobNativeCard> {
  // 광고는 카드가 소유하지 않고 ListAdCache 가 (unitId+factory) 키로 보관.
  // 스크롤로 벗어나면 PlatformView 는 unmount(가벼움), 인스턴스는 캐시에 살아 있어
  // 되돌아올 때 재로드 없이 다시 mount 만. (KeepAlive·프리로드 풀 불필요)
  late final String _key = '${widget.adUnitId}|${widget.isEv}';
  String get _factory => widget.isEv ? 'stationCardListEv' : 'stationCardList';

  // 옆 스테이션 카드와 동일 높이로 — 슬롯에 빈 공간 없이 꽉 차게.
  // Gas = GasStationCard(BrandLogo 40 + padding 13×2 ≈ 68dp) 와 동일.
  double get _height => widget.isEv ? 96 : 68;

  @override
  void initState() {
    super.initState();
    // 이 카드가 화면 근처에서 빌드되는 시점에 비로소 로드(지연) → PlatformView mount 분산.
    ListAdCache.ensureLoaded(_key, widget.adUnitId, _factory);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ListAdCache.readyNotifier(_key),
      builder: (context, ready, _) {
        final ad = ListAdCache.ad(_key);
        if (!ready || ad == null) {
          // 로딩 중/실패 — 옆 카드와 동일 높이로 자리만 예약(레이아웃 점프 방지).
          return SizedBox(height: _height + widget.margin.vertical);
        }
        return Container(
          margin: widget.margin,
          height: _height,
          // 네이티브 광고(플랫폼 뷰)는 XML 의 라운드가 콘텐츠에 가려 각져 보임 →
          // Flutter 단에서 ClipRRect 로 강제 라운드(스테이션 카드와 동일 14dp).
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            // 플랫폼뷰(광고) 리페인트를 격리 → 스크롤 시 리스트 전체 리페인트 방지(잭 완화)
            child: RepaintBoundary(child: AdWidget(ad: ad)),
          ),
        );
      },
    );
  }
}

/// 홈 상단 배너 AdMob 네이티브 (2단 카드, factoryId=stationCardTop).
/// DkswTopBanner 의 admobFallback 으로 사용 — 콘솔 house ad 없을 때 노출.
/// 로드 전·실패 시 높이 0(빈 자리).
class TopBannerAdmobCard extends StatefulWidget {
  const TopBannerAdmobCard({super.key});

  @override
  State<TopBannerAdmobCard> createState() => _TopBannerAdmobCardState();
}

class _TopBannerAdmobCardState extends State<TopBannerAdmobCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
  }

  void _load() {
    _ad = NativeAd(
      adUnitId: AdUnitIds.topBanner,
      factoryId: 'stationCardTop',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
            height: 116, child: RepaintBoundary(child: AdWidget(ad: _ad!))),
      ),
    );
  }
}

/// 콘솔에서 등록한 house ad 카드. 우리가 직접 그림 (자유 디자인).
class HouseAdCard extends StatefulWidget {
  final HouseAd ad;
  /// EV 탭 컨텍스트 — 좌측 4dp 컬러 스트립 노출.
  final bool isEv;
  final EdgeInsets margin;

  const HouseAdCard({
    super.key,
    required this.ad,
    this.isEv = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<HouseAdCard> createState() => _HouseAdCardState();
}

class _HouseAdCardState extends State<HouseAdCard> {
  bool _impressionReported = false;
  // native ad card 와 동일 — 옆 스테이션 카드 높이(Gas 68 / EV 96)에 맞춤.
  double get _height => widget.isEv ? 96 : 68;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markImpression();
    });
  }

  void _markImpression() {
    if (_impressionReported) return;
    _impressionReported = true;
    HouseAdCache.reportImpression(widget.ad.id);
  }

  Future<void> _onTap() async {
    HouseAdCache.reportClick(widget.ad.id);
    final url = widget.ad.ctaUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF12141A) : Colors.white;
    final borderColor =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;

    final inner = widget.ad.isStructured
        ? _StructuredAdContent(ad: widget.ad, isEv: widget.isEv)
        : _BannerAdContent(ad: widget.ad);

    return Container(
      margin: widget.margin,
      height: _height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onTap,
          child: widget.isEv
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: AppColors.gasBlue),
                    Expanded(child: inner),
                  ],
                )
              : inner,
        ),
      ),
    );
  }
}

/// AdMob 카드와 동일한 구조: 좌측 아이콘 + 가운데 헤드라인+본문 + 우측 CTA.
class _StructuredAdContent extends StatelessWidget {
  final HouseAd ad;
  final bool isEv;
  const _StructuredAdContent({required this.ad, required this.isEv});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final labelBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE8ECF0);

    final iconSize = isEv ? 44.0 : 38.0;
    final headlineSize = isEv ? 13.0 : 13.0;
    final ctaHeight = isEv ? 28.0 : 28.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isEv ? 12 : 14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: AppColors.gasBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: DkswCore.resolveAssetUrl(ad.imageUrl),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(Icons.image_outlined,
                  size: iconSize * 0.45, color: AppColors.gasBlue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: labelBg,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'AD',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: secondary,
                          letterSpacing: 0.2,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ad.headline ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: headlineSize,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((ad.bodyText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ad.bodyText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: secondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((ad.ctaLabel ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              height: ctaHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.gasBlue,
                borderRadius: BorderRadius.circular(ctaHeight / 2),
              ),
              alignment: Alignment.center,
              child: Text(
                ad.ctaLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 구조화 텍스트 없이 등록된 광고 — 풀폭 이미지 배너로 폴백.
class _BannerAdContent extends StatelessWidget {
  final HouseAd ad;
  const _BannerAdContent({required this.ad});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: DkswCore.resolveAssetUrl(ad.imageUrl),
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'AD',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
