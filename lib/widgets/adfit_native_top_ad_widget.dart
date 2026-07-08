import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 상단/상세 카드 (2단 카드 스타일).
///
/// 네이티브 팩토리(AdFitNativeTopPlatformViewFactory)가 로드 성공/최종 실패를
/// per-view MethodChannel 로 알려줌 — 실패(광고 없음) 시 자리를 접어(shrink)
/// 빈 회색 박스가 남지 않게 한다. 로드 중엔 네이티브 placeholder(스켈레톤) 표시.
/// 폭은 XML 패딩을 없애고 [padding] 으로만 준다(AdMob 상단 카드와 동일 폭).
class AdFitNativeTopAdWidget extends StatefulWidget {
  final String adCode;

  /// 광고가 보일 때만 적용되는 바깥 여백 — 실패로 접힐 땐 여백도 없음.
  final EdgeInsets padding;

  /// 최종 실패(no-fill) 시 대신 그릴 위젯(하우스 폴백). 없으면 자리 접음.
  final Widget? fallback;

  const AdFitNativeTopAdWidget({
    super.key,
    required this.adCode,
    this.padding = EdgeInsets.zero,
    this.fallback,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_top';

  /// 스폰서줄 + 제목2줄 + 90dp 미디어 + 내부패딩 기준 (XML 루트 패딩 제거 후 실측)
  static const double slotHeight = 144;

  @override
  State<AdFitNativeTopAdWidget> createState() => _AdFitNativeTopAdWidgetState();
}

class _AdFitNativeTopAdWidgetState extends State<AdFitNativeTopAdWidget> {
  MethodChannel? _events;
  bool _failed = false;

  void _onViewCreated(int id) {
    _events = MethodChannel('com.dksw.charge/adfit_top_events_$id')
      ..setMethodCallHandler((call) async {
        if (!mounted) return;
        if (call.method == 'failed') setState(() => _failed = true);
        if (call.method == 'loaded' && _failed) setState(() => _failed = false);
      });
  }

  @override
  void dispose() {
    _events?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) return const SizedBox.shrink();
    if (widget.adCode.isEmpty || _failed) {
      return widget.fallback ?? const SizedBox.shrink();
    }

    return Padding(
      padding: widget.padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: double.infinity,
          height: AdFitNativeTopAdWidget.slotHeight,
          child: buildAdFitSurfaceAndroidView(
            viewType: AdFitNativeTopAdWidget._viewType,
            creationParams: <String, dynamic>{'clientId': widget.adCode},
            onPlatformViewCreated: _onViewCreated,
          ),
        ),
      ),
    );
  }
}
