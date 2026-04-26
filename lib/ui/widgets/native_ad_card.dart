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
  final EdgeInsets margin;

  const AdMobNativeCard({
    super.key,
    required this.adUnitId,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<AdMobNativeCard> createState() => _AdMobNativeCardState();
}

class _AdMobNativeCardState extends State<AdMobNativeCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  static const double _height = 64; // station card 와 동일

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
  }

  void _load() {
    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: 'stationCardList',
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
  final EdgeInsets margin;

  const HouseAdCard({
    super.key,
    required this.ad,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<HouseAdCard> createState() => _HouseAdCardState();
}

class _HouseAdCardState extends State<HouseAdCard> {
  bool _impressionReported = false;
  static const double _height = 64;

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
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                DkswCore.resolveAssetUrl(widget.ad.imageUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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
          ),
        ),
      ),
    );
  }
}
