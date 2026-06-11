import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 1:1 문의 화면 상단 AdMob 네이티브 광고.
///
/// Android 커스텀 팩토리 `inquiryCard`(native_ad_inquiry.xml)로 렌더 —
/// 세로 카드(AD 뱃지+광고주 / 큰 헤드라인 / 풀폭 그라데이션 CTA + 그라데이션 테두리).
/// 로딩 전·실패 시 높이 0(SizedBox.shrink)으로 레이아웃 방해 안 함.
class InquiryNativeAdBanner extends StatefulWidget {
  const InquiryNativeAdBanner({super.key});

  /// 1:1 문의 네이티브 광고 단위 (charge AdMob).
  static const String adUnitId = 'ca-app-pub-8640148276009977/8336523698';

  @override
  State<InquiryNativeAdBanner> createState() => _InquiryNativeAdBannerState();
}

class _InquiryNativeAdBannerState extends State<InquiryNativeAdBanner> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ad = NativeAd(
      adUnitId: InquiryNativeAdBanner.adUnitId,
      factoryId: 'inquiryCard',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[InquiryNativeAd] failed: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    // 좌우 마진 0 — core InquiryScreen 의 ListView 패딩(16)만 적용돼
    // '내 문의 N건' 헤더 카드와 동일 폭이 되게(배너에 별도 마진 주면 이중 = 더 좁아짐).
    return SizedBox(
      // 세로 카드 고정 높이 — 2줄 헤드라인 + 풀폭 CTA 가 잘리지 않게.
      height: 188,
      width: double.infinity,
      child: AdWidget(ad: ad),
    );
  }
}
