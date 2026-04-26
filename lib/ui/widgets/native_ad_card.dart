import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/house_ad_service.dart';

/// 인-리스트 광고 카드.
///
/// 두 종류:
///  - AdMob 네이티브 광고 (factoryId=stationCardList) — 슬롯 4·8.
///  - House ad (콘솔 등록) — 슬롯 4·8 (bypass) 또는 12+.
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
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  double get _height => widget.isEv ? 80 : 64; // EV 카드와 동일 / Gas 카드와 동일

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
  }

  void _load() {
    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: widget.isEv ? 'stationCardListEv' : 'stationCardList',
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
    if (_failed) return const SizedBox.shrink();
    if (!_loaded || _ad == null) {
      return SizedBox(height: _height + widget.margin.vertical);
    }
    return Container(
      margin: widget.margin,
      height: _height,
      child: AdWidget(ad: _ad!),
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
  double get _height => widget.isEv ? 80 : 64;

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
            child: Image.network(
              DkswCore.resolveAssetUrl(ad.imageUrl),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.image_outlined,
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
        Image.network(
          DkswCore.resolveAssetUrl(ad.imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
