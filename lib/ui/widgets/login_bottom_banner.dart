import 'package:cached_network_image/cached_network_image.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/ad_cta.dart';
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
  static const double _height = 68; // 카드형 — 리스트 카드(stationCardList)와 동일 톤
  // 풀폭 배너는 원본 비율대로 폭을 꽉 채우고, 세로가 긴 에셋이 로그인 화면을
  // 밀어내지 않도록 이 높이에서만 잘라냄. (권장 1080×200 → 약 96)
  static const double _bannerMaxHeight = 132;

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
    await openAdCta(context, url: ad.ctaUrl, ctaType: ad.ctaType);
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == 'off') return const SizedBox.shrink();

    // 아이패드/태블릿 대비 — 로그인 화면은 폭 제약이 없어 배너가 화면 전체로
    // 늘어나면 비율상 높이가 컷오프를 넘겨 잘린다. 폰 폭 수준(480)으로 제한하고
    // 가운데 정렬 → 어떤 기기에서도 폰과 같은 크기·비율로 노출.
    Widget constrain(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        );

    // 하우스 배너 (광고주 이미지 — 아웃링크)
    if ((_mode == 'house' || _mode == 'auto') && _house != null) {
      return constrain(_houseBanner(context, _house!));
    }
    // AdMob (admob 모드, 또는 auto 에서 하우스 없음 확정 후)
    final wantAdmob =
        _mode == 'admob' || (_mode == 'auto' && _houseChecked && _house == null);
    if (wantAdmob && _admobLoaded && _admob != null && !_admobFailed) {
      return constrain(Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        height: _height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: RepaintBoundary(child: AdWidget(key: GlobalObjectKey(_admob!), ad: _admob!)),
        ),
      ));
    }
    // 로딩 중/없음 — 자리 예약 없이 접음 (로그인 화면 레이아웃 유지)
    return const SizedBox.shrink();
  }

  // 하우스 광고 2형태 — 콘솔 등록의 '표시 형태'를 따름.
  //  · banner(또는 비구조화): 풀폭 이미지 배너
  //  · card + 구조화 텍스트: 앱 리스트 카드 톤의 [아이콘|헤드라인·본문|CTA] 행
  Widget _houseBanner(BuildContext context, FallbackAd ad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final useCard = ad.displayStyle == 'card' && ad.isStructured;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _onHouseTap,
          child: Container(
            // 카드형은 리스트 카드와 동일 고정 높이, 풀폭 배너는 에셋 원본 비율.
            height: useCard ? _height : null,
            decoration: BoxDecoration(
              color: useCard
                  ? (isDark ? const Color(0xFF12141A) : Colors.white)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: useCard ? _cardContent(context, ad) : _imageContent(ad),
          ),
        ),
      ),
    );
  }

  // 풀폭 이미지 배너 + AD 뱃지(우상단 모서리)
  //
  // 폭은 항상 꽉 채우고 높이는 에셋 원본 비율을 따른다. 고정 비율 + contain 이면
  // 권장(1080×200)과 다른 크리에이티브에서 좌우가 크게 비어 보이기 때문.
  Widget _imageContent(FallbackAd ad) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _bannerMaxHeight),
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: DkswCore.resolveAssetUrl(ad.imageUrl),
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
          const Positioned(top: 6, right: 6, child: _AdBadge(onImage: true)),
        ],
      ),
    );
  }

  // 앱 카드 톤 구조화 행 — 홈 리스트 하우스 카드와 동일 문법
  Widget _cardContent(BuildContext context, FallbackAd ad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final hasCta = (ad.ctaLabel ?? '').isNotEmpty;
    // AD 표기는 카드 안쪽 텍스트 흐름을 끊지 않도록 우상단 모서리로 뺀다.
    // CTA 가 없으면 헤드라인이 뱃지 밑으로 파고들 수 있어 오른쪽 여백을 더 준다.
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, 12, hasCta ? 14 : 40, 12),
          child: _cardRow(ad, primary, secondary),
        ),
        const Positioned(top: 6, right: 8, child: _AdBadge()),
      ],
    );
  }

  Widget _cardRow(FallbackAd ad, Color primary, Color secondary) {
    return Row(
      children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.gasBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: DkswCore.resolveAssetUrl(ad.imageUrl),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const Icon(Icons.campaign_rounded,
                  size: 20, color: AppColors.gasBlue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.headline ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primary,
                      height: 1.2),
                ),
                if ((ad.bodyText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ad.bodyText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: secondary, height: 1.2),
                  ),
                ],
              ],
            ),
          ),
          if ((ad.ctaLabel ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.gasBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                ad.ctaLabel!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
      ],
    );
  }
}

/// 광고 표기 뱃지 — 카드/이미지 모서리 공용.
class _AdBadge extends StatelessWidget {
  final bool onImage;
  const _AdBadge({this.onImage = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = onImage
        ? Colors.black.withValues(alpha: 0.45)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE8ECF0));
    final fg = onImage
        ? Colors.white
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'AD',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
