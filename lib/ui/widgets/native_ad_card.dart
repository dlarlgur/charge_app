import 'dart:math';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/house_ad_service.dart';

enum HouseAdSlot { homeTop, homeList }

enum _Source { admob, house, none }

/// Hybrid 광고 카드 — house ad(콘솔 등록) 와 AdMob native 를 모드별로 섞어 노출.
///
/// AdMob 측은 factoryId="stationCard" 로 등록된 플랫폼 네이티브 레이아웃
/// (Android: layout/native_ad_card.xml, iOS: StationCardNativeAdFactory.swift)
/// 으로 렌더 → 앱 카드와 시각 통합.
///
/// House ad 측은 우리가 직접 그림 → 자유 디자인.
class NativeAdCard extends StatefulWidget {
  /// AdMob 광고 단위 ID (네이티브 광고 고급형).
  final String adUnitId;

  /// 위치 — house ad 캐시 매칭 + 카드 높이 결정.
  final HouseAdSlot slot;

  /// (deprecated, NativeTemplateStyle 시절 잔존) — 무시됨.
  /// factoryId 방식은 layout 으로 사이즈 결정.
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
        _source = _Source.admob;
        _loadAdmob();
        break;
      case HouseAdMode.mix:
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

  String get _factoryId => widget.slot == HouseAdSlot.homeTop
      ? 'stationCardTop'   // 강조형 큰 배너
      : 'stationCardList'; // 인라인 (스테이션 카드와 동일한 행)

  void _loadAdmob() {
    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      factoryId: _factoryId,
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

  /// 카드 높이 — Android XML / iOS layout 의 실제 컨텐츠 높이와 정확히 일치.
  /// top  : 14 padding + 80 icon + 14 padding = 108dp (강조형 큰 배너)
  /// list : 13 padding + 38 icon + 13 padding = 64dp (스테이션 카드와 동일)
  double get _height => widget.slot == HouseAdSlot.homeTop ? 108 : 64;

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
      if (!_admobLoaded || _ad == null) {
        // 로딩 중: 점프 방지용 빈 자리.
        return SizedBox(height: _height + widget.margin.vertical);
      }
      return Container(
        margin: widget.margin,
        height: _height,
        child: AdWidget(ad: _ad!),
      );
    }
    return const SizedBox.shrink();
  }
}

/// House ad 자체 렌더링 — 앱 카드와 동일 코너/보더 + 'AD' 라벨.
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

    return Container(
      margin: margin,
      height: height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
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
              // 'AD' 라벨 — 의무 표기
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
