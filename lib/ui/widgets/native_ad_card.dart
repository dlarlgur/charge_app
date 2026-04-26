import 'dart:math';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/house_ad_service.dart';

/// 하이브리드 광고 카드.
///
/// 우선순위:
///  1. House ad (콘솔 직접 등록):
///     - mode=solo     : AdMob 없이 house 만 노출
///     - mode=fallback : AdMob 우선, 실패 시 house 로 대체
///     - mode=mix      : weight(=house weight, AdMob=1) 가중치 분배
///  2. House ad 없음: AdMob 만
///
/// 두 경로 모두 실패하면 빈 위젯.
class NativeAdCard extends StatefulWidget {
  /// AdMob 광고 단위 ID.
  final String adUnitId;

  /// 위치 — house ad 캐시 매칭용.
  final HouseAdSlot slot;

  /// AdMob 측 템플릿 크기.
  final TemplateType type;
  final EdgeInsets margin;

  const NativeAdCard({
    super.key,
    required this.adUnitId,
    required this.slot,
    this.type = TemplateType.small,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

enum HouseAdSlot { homeTop, homeList }

enum _Source { admob, house, none }

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _admobLoaded = false;
  bool _admobFailed = false;
  _Source _source = _Source.none;
  HouseAd? _houseAd;
  bool _houseImpressionReported = false;

  HouseAd? _pickHouseAd() => switch (widget.slot) {
        HouseAdSlot.homeTop => HouseAdCache.homeTop,
        HouseAdSlot.homeList => HouseAdCache.homeList,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_source == _Source.none) _decide();
  }

  void _decide() {
    _houseAd = _pickHouseAd();
    if (_houseAd == null) {
      _source = _Source.admob;
      _loadAdmob();
      return;
    }
    switch (_houseAd!.mode) {
      case HouseAdMode.solo:
        _source = _Source.house;
        _markImpression();
        break;
      case HouseAdMode.fallback:
        _source = _Source.admob; // AdMob 시도 → 실패 시 house 로 전환
        _loadAdmob();
        break;
      case HouseAdMode.mix:
        // weight 가중치: house=weight, AdMob=1
        final w = _houseAd!.weight.clamp(1, 100);
        final pickHouse = Random().nextInt(w + 1) < w;
        if (pickHouse) {
          _source = _Source.house;
          _markImpression();
        } else {
          _source = _Source.admob;
          _loadAdmob();
        }
        break;
    }
    if (mounted) setState(() {});
  }

  void _markImpression() {
    if (_houseImpressionReported || _houseAd == null) return;
    _houseImpressionReported = true;
    HouseAdCache.reportImpression(_houseAd!.id);
  }

  void _loadAdmob() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF12141A) : Colors.white;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final cornerRadius = widget.type == TemplateType.small ? 12.0 : 14.0;

    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _admobLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _admobFailed = true;
          // fallback 모드면 house 로 전환
          if (_houseAd != null && _houseAd!.mode == HouseAdMode.fallback) {
            _source = _Source.house;
            _markImpression();
          }
          if (mounted) setState(() {});
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.type,
        mainBackgroundColor: cardColor,
        cornerRadius: cornerRadius,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: AppColors.gasBlue,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: primary,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: secondary,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: secondary,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 11,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _onHouseTap() async {
    if (_houseAd == null) return;
    HouseAdCache.reportClick(_houseAd!.id);
    final url = _houseAd!.ctaUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  double get _height => widget.type == TemplateType.small ? 90 : 320;

  @override
  Widget build(BuildContext context) {
    if (_source == _Source.house && _houseAd != null) {
      return _HouseAdView(
        ad: _houseAd!,
        slot: widget.slot,
        margin: widget.margin,
        height: _height,
        onTap: _onHouseTap,
      );
    }
    if (_source == _Source.admob) {
      if (_admobFailed) return const SizedBox.shrink();
      if (!_admobLoaded || _ad == null) return SizedBox(height: _height);
      return Container(
        margin: widget.margin,
        height: _height,
        child: AdWidget(ad: _ad!),
      );
    }
    return const SizedBox.shrink();
  }
}

/// House ad 자체 렌더링 — 앱 카드 디자인과 통합되도록 우리가 직접 그림.
class _HouseAdView extends StatelessWidget {
  final HouseAd ad;
  final HouseAdSlot slot;
  final EdgeInsets margin;
  final double height;
  final VoidCallback onTap;

  const _HouseAdView({
    required this.ad,
    required this.slot,
    required this.margin,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF12141A) : Colors.white;
    final borderColor = isDark
        ? AppColors.darkCardBorder
        : AppColors.lightCardBorder;
    final radius = slot == HouseAdSlot.homeTop ? 12.0 : 14.0;

    return Container(
      margin: margin,
      height: height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                DkswCore.resolveAssetUrl(ad.imageUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              // '광고' 라벨 — 의무 표기 (네이티브 광고 가이드라인).
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
