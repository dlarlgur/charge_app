import 'package:cached_network_image/cached_network_image.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/ad_fallback_cache.dart';
import '../../data/services/ad_service.dart';

/// 로그인 화면 하단 배너 — 첫 로그인 게이트 + 설정→로그인 두 진입 모두 이 위젯 하나.
///
/// 콘솔 광고 페이지 '로그인 하단 배너' 모드로 제어 (원격설정 login_banner[_ios]):
///  · off   : 아무것도 그리지 않음 (영역 자체 없음 — 기본)
///  · house : 하우스 광고만 (placement=login_bottom, 없으면 접힘)
///  · admob : AdMob 네이티브만
///  · auto  : 하우스 우선, 없으면 AdMob 폴백
/// 하우스 광고의 iOS/AOS 타겟은 광고 등록의 플랫폼 라디오(서버 필터)로 처리됨.
class LoginBottomBanner extends StatefulWidget {
  const LoginBottomBanner({super.key});

  @override
  State<LoginBottomBanner> createState() => _LoginBottomBannerState();
}

class _LoginBottomBannerState extends State<LoginBottomBanner> {
  static const double _height = 68; // 리스트 카드(stationCardList)와 동일 톤

  late final String _mode = LoginBannerConfig.mode;
  FallbackAd? _house;
  bool _houseChecked = false;

  NativeAd? _admob;
  bool _admobLoaded = false;
  bool _admobFailed = false;

  @override
  void initState() {
    super.initState();
    if (_mode == 'house' || _mode == 'auto') {
      AdFallbackCache.ensure('login_bottom').then((ad) {
        if (!mounted) return;
        setState(() {
          _house = ad;
          _houseChecked = true;
        });
        if (ad == null && _mode == 'auto') _loadAdmob();
      });
    } else if (_mode == 'admob') {
      _loadAdmob();
    }
  }

  void _loadAdmob() {
    _admob = NativeAd(
      adUnitId: AdUnitIds.loginBottom,
      factoryId: 'stationCardList',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _admobLoaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _admobFailed = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _admob?.dispose();
    super.dispose();
  }

  Future<void> _onHouseTap() async {
    final ad = _house;
    if (ad == null) return;
    final url = ad.ctaUrl;
    if (url == null || url.isEmpty || ad.ctaType == 'none') return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == 'off') return const SizedBox.shrink();

    // 하우스 배너 (광고주 이미지 — 아웃링크)
    if ((_mode == 'house' || _mode == 'auto') && _house != null) {
      return _houseBanner(context, _house!);
    }
    // AdMob (admob 모드, 또는 auto 에서 하우스 없음 확정 후)
    final wantAdmob =
        _mode == 'admob' || (_mode == 'auto' && _houseChecked && _house == null);
    if (wantAdmob && _admobLoaded && _admob != null && !_admobFailed) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        height: _height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: RepaintBoundary(child: AdWidget(key: GlobalObjectKey(_admob!), ad: _admob!)),
        ),
      );
    }
    // 로딩 중/없음 — 자리 예약 없이 접음 (로그인 화면 레이아웃 유지)
    return const SizedBox.shrink();
  }

  Widget _houseBanner(BuildContext context, FallbackAd ad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _onHouseTap,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      ),
    );
  }
}
