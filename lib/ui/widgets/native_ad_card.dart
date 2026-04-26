import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/theme/app_colors.dart';

/// 앱 카드 디자인에 맞춘 네이티브 광고 위젯 (NativeTemplateStyle 사용).
///
/// - [adUnitId]: AdMob 콘솔에서 발급받은 네이티브 광고 단위 ID.
/// - [type]: small (홈탭 상단 배너 자리), medium (리스트 인-피드).
/// - 로드 실패하면 자리만 차지하지 않고 SizedBox.shrink 로 사라짐.
class NativeAdCard extends StatefulWidget {
  final String adUnitId;
  final TemplateType type;
  final EdgeInsets margin;

  const NativeAdCard({
    super.key,
    required this.adUnitId,
    this.type = TemplateType.small,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
  }

  void _load() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF12141A) : Colors.white;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final cornerRadius = widget.type == TemplateType.small ? 12.0 : 14.0;

    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
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

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (!_loaded || _ad == null) {
      // 로드 전 빈 placeholder — 갑작스런 레이아웃 점프 방지.
      return SizedBox(
        height: widget.type == TemplateType.small ? 90 : 320,
      );
    }
    final h = widget.type == TemplateType.small ? 90.0 : 320.0;
    return Container(
      margin: widget.margin,
      height: h,
      child: AdWidget(ad: _ad!),
    );
  }
}
