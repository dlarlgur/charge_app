import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/ad_cta.dart';
import '../../data/services/ad_service.dart';
import '../../data/services/house_ad_service.dart';
import '../../data/services/list_ad_cache.dart';
import '../../data/services/ad_fallback_cache.dart';
import '../../widgets/adfit_native_list_ad_widget.dart';
import '../../widgets/adfit_native_top_ad_widget.dart';

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

  /// 리스트 위치 — AdFit 모드에서 위치별 AdFit 단위 매핑에 사용.
  final int listPosition;

  /// EV 탭 컨텍스트 — 좌측 4dp 컬러 스트립이 있는 layout 사용.
  final bool isEv;
  final EdgeInsets margin;

  const AdMobNativeCard({
    super.key,
    required this.adUnitId,
    this.listPosition = 4,
    this.isEv = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<AdMobNativeCard> createState() => _AdMobNativeCardState();
}

class _AdMobNativeCardState extends State<AdMobNativeCard> {
  // 광고는 카드가 소유하지 않고 ListAdCache 가 키로 보관.
  // 스크롤로 벗어나면 PlatformView 는 unmount(가벼움), 인스턴스는 캐시에 살아 있어
  // 되돌아올 때 재로드 없이 다시 mount 만. (KeepAlive·프리로드 풀 불필요)
  // ⚠️ 키에 listPosition 포함 필수 — 같은 유닛 ID 가 여러 슬롯에 쓰이면(디버그 테스트유닛,
  //   또는 상용 긴 목록의 fallback) 하나의 NativeAd 를 여러 AdWidget 이 물어
  //   "already in the Widget tree" 크래시. 슬롯별 인스턴스로 분리한다.
  late final String _key =
      '${widget.adUnitId}|${widget.isEv}|${widget.listPosition}';
  String get _factory => widget.isEv ? 'stationCardListEv' : 'stationCardList';

  // 옆 스테이션 카드와 동일 높이로 — 슬롯에 빈 공간 없이 꽉 차게.
  // Gas = GasStationCard(BrandLogo 40 + padding 13×2 ≈ 68dp) 와 동일.
  double get _height => widget.isEv ? 96 : 68;

  @override
  void initState() {
    super.initState();
    // 이 카드가 화면 근처에서 빌드되는 시점에 비로소 로드(지연) → PlatformView mount 분산.
    // AdMob 모드가 아니면 AdMob 로드 자체를 하지 않음 (원격설정 ads_network 전환).
    if (AdNetworkConfig.current == AdNetwork.admob) {
      ListAdCache.ensureLoaded(_key, widget.adUnitId, _factory);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (AdNetworkConfig.current) {
      case AdNetwork.off:
        return const SizedBox.shrink();
      case AdNetwork.adfit:
        return Container(
          margin: widget.margin,
          height: _height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: RepaintBoundary(
              child: AdFitNativeListAdWidget(
                adCode: AdFitUnitIds.forPosition(widget.listPosition),
                height: _height,
                isEv: widget.isEv,
              ),
            ),
          ),
        );
      case AdNetwork.admob:
        break;
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ListAdCache.readyNotifier(_key),
      builder: (context, ready, _) {
        final ad = ListAdCache.ad(_key);
        if (!ready || ad == null) {
          // 재시도까지 전부 실패(no-fill) → 자리 접기. 그 전엔 옆 카드와 동일
          // 높이로 자리만 예약(로드 완료 시 레이아웃 점프 방지).
          return ValueListenableBuilder<bool>(
            valueListenable: ListAdCache.failedNotifier(_key),
            builder: (context, failed, _) => failed
                ? const SizedBox.shrink()
                : SizedBox(height: _height + widget.margin.vertical),
          );
        }
        return Container(
          margin: widget.margin,
          height: _height,
          // 네이티브 광고(플랫폼 뷰)는 XML 의 라운드가 콘텐츠에 가려 각져 보임 →
          // Flutter 단에서 ClipRRect 로 강제 라운드(스테이션 카드와 동일 14dp).
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            // 플랫폼뷰(광고) 리페인트를 격리 → 스크롤 시 리스트 전체 리페인트 방지(잭 완화)
            child: RepaintBoundary(child: AdWidget(key: GlobalObjectKey(ad), ad: ad)),
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
    if (_ad == null && AdNetworkConfig.current == AdNetwork.admob) _load();
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
    switch (AdNetworkConfig.current) {
      case AdNetwork.off:
        return const SizedBox.shrink();
      case AdNetwork.adfit:
        return RepaintBoundary(
          child: AdFitNativeTopAdWidget(
            adCode: AdFitUnitIds.topBanner,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            fallback: const HouseFallbackAd(placement: 'home_top'),
          ),
        );
      case AdNetwork.admob:
        break;
    }
    // AdMob 실패(no-fill) → 하우스 폴백. 로드 중엔 자리 접음(깜빡임 방지).
    if (_failed) return const HouseFallbackAd(placement: 'home_top');
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
            height: 116, child: RepaintBoundary(child: AdWidget(key: GlobalObjectKey(_ad!), ad: _ad!))),
      ),
    );
  }
}

/// 주유소·충전소 상세 화면 상단 카드 바로 아래 네이티브 광고.
/// 강조형(factoryId=stationCardTop, native_ad_top.xml) 카드 — 상세 헤더 카드와
/// 동일한 좌우 마진(16) + 14dp 라운드로 디자인 일관성 유지.
/// 로드 전·실패 시 높이 0(SizedBox.shrink) → 레이아웃 점프/방해 없음.
class StationDetailNativeAd extends StatefulWidget {
  const StationDetailNativeAd({super.key});

  @override
  State<StationDetailNativeAd> createState() => _StationDetailNativeAdState();
}

class _StationDetailNativeAdState extends State<StationDetailNativeAd> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null && AdNetworkConfig.current == AdNetwork.admob) _load();
  }

  void _load() {
    _ad = NativeAd(
      adUnitId: AdUnitIds.stationDetailNative,
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
    switch (AdNetworkConfig.current) {
      case AdNetwork.off:
        return const SizedBox.shrink();
      case AdNetwork.adfit:
        return RepaintBoundary(
          child: AdFitNativeTopAdWidget(
            adCode: AdFitUnitIds.detail,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            fallback: const HouseFallbackAd(
                placement: 'station_detail',
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8)),
          ),
        );
      case AdNetwork.admob:
        break;
    }
    if (_failed) {
      return const HouseFallbackAd(
          placement: 'station_detail',
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8));
    }
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      // 헤더 카드 바로 아래 — 좌우 16(카드와 동일), 위 약간 띄우고 탭과 간격.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
            height: 116, child: RepaintBoundary(child: AdWidget(key: GlobalObjectKey(_ad!), ad: _ad!))),
      ),
    );
  }
}

/// 콘솔에서 등록한 house ad 카드. 우리가 직접 그림 (자유 디자인).
class HouseAdCard extends StatefulWidget {
  final HouseAd ad;

  /// 같은 위치의 광고 전체 — 2개+ 면 캐러셀 순환. null/1개면 [ad] 단건.
  final List<HouseAd>? carousel;

  /// EV 탭 컨텍스트 — 좌측 4dp 컬러 스트립 노출.
  final bool isEv;
  final EdgeInsets margin;

  const HouseAdCard({
    super.key,
    required this.ad,
    this.carousel,
    this.isEv = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  @override
  State<HouseAdCard> createState() => _HouseAdCardState();
}

class _HouseAdCardState extends State<HouseAdCard> {
  // native ad card 와 동일 — 옆 스테이션 카드 높이(Gas 68 / EV 96)에 맞춤.
  double get _height => widget.isEv ? 96 : 68;

  // 홈 리스트 캐러셀 간격(초) — 로그인/상단 배너와 동일 원격설정 키 규칙.
  double get _rotateSec =>
      (DkswCore.config<num>('house_rotate_sec_home_list') ?? 0).toDouble();

  late List<HouseAd> _ads;
  int _current = 0;
  Timer? _timer;
  final Set<int> _impressed = {};

  HouseAd get _ad => _ads[_current % _ads.length];

  @override
  void initState() {
    super.initState();
    final list = widget.carousel;
    _ads = (list != null && list.isNotEmpty) ? list : [widget.ad];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markImpression(_ad);
    });
    if (_ads.length > 1 && _rotateSec > 0) {
      _timer = Timer.periodic(
        Duration(milliseconds: (_rotateSec * 1000).round()),
        (_) {
          if (!mounted) return;
          setState(() => _current = (_current + 1) % _ads.length);
          _markImpression(_ad);
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _markImpression(HouseAd ad) {
    if (_impressed.add(ad.id)) HouseAdCache.reportImpression(ad.id);
  }

  Future<void> _onTap() async {
    HouseAdCache.reportClick(_ad.id);
    await openAdCta(context, url: _ad.ctaUrl, ctaType: _ad.ctaType);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF12141A) : Colors.white;
    final borderColor =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;

    final inner = _ad.isStructured
        ? _StructuredAdContent(ad: _ad, isEv: widget.isEv)
        : _BannerAdContent(ad: _ad);

    final content = Material(
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
    );

    // 캐러셀(2개+·간격 설정)이면 가로 슬라이드 전환. 단건이면 그대로.
    final Widget body = _ads.length > 1
        ? AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final incoming =
                  child.key == ValueKey<int>(_ad.id);
              final slide = Tween<Offset>(
                begin: Offset(incoming ? 1.0 : -1.0, 0),
                end: Offset.zero,
              ).animate(anim);
              return ClipRect(
                child: SlideTransition(position: slide, child: child),
              );
            },
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: [...previous, if (current != null) current],
            ),
            child: KeyedSubtree(key: ValueKey<int>(_ad.id), child: content),
          )
        : content;

    return Container(
      margin: widget.margin,
      height: _height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
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
    final labelBg =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8ECF0);

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

/// 폴백 하우스 광고 카드 — 네트워크(AdMob/AdFit) no-fill 시 상단/상세 자리에 노출.
/// 캐시에 폴백 광고 없으면 SizedBox.shrink() (자리 접음).
class HouseFallbackAd extends StatelessWidget {
  final String placement; // 'home_top' | 'station_detail'
  final EdgeInsets padding;

  const HouseFallbackAd({
    super.key,
    required this.placement,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  // 폴백 광고도 콘솔 통계에 잡히도록 노출 1회/클릭 보고 (세션당 광고별 1회).
  static final Set<int> _impressed = {};
  static void _trackImpressionOnce(int adId) {
    if (_impressed.add(adId)) DkswCore.trackAdImpression(adId);
  }

  Future<void> _onTap(BuildContext context, FallbackAd ad) async {
    DkswCore.trackAdClick(ad.id);
    await openAdCta(context, url: ad.ctaUrl, ctaType: ad.ctaType);
  }

  @override
  Widget build(BuildContext context) {
    final ad = AdFallbackCache.at(placement);
    if (ad == null || ad.imageUrl.isEmpty) return const SizedBox.shrink();
    _trackImpressionOnce(ad.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkSurface1 : Colors.white;
    final border =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final imgUrl = DkswCore.resolveAssetUrl(ad.imageUrl);

    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _onTap(context, ad),
          child: ad.displayStyle == 'banner' || !ad.isStructured
              // 풀폭 배너 — 이미지만
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 5,
                    child: CachedNetworkImage(
                      imageUrl: imgUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                )
              // 2단 카드 — 아이콘 + 헤드라인/본문 + (광고)
              : Container(
                  height: 116,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border, width: 0.5),
                  ),
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: imgUrl,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const SizedBox(width: 90, height: 90),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: muted.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('AD',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: muted)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(ad.headline ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ink)),
                            if ((ad.bodyText ?? '').isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(ad.bodyText!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: muted)),
                            ],
                          ],
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
