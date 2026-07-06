import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 상단/상세 카드 (2단 카드 스타일).
///
/// 네이티브 팩토리(AdFitNativeTopPlatformViewFactory)가 로드 성공/최종 실패를
/// per-view MethodChannel 로 알려줌 — 실패 시 자리를 접어(shrink) 빈 회색
/// 박스가 남지 않게 한다. 로드 중에는 네이티브 placeholder(스켈레톤) 표시.
class AdFitNativeTopAdWidget extends StatefulWidget {
  final String adCode;

  /// 광고가 보일 때만 적용되는 바깥 여백 — 실패로 접힐 땐 여백도 없음.
  final EdgeInsets padding;

  const AdFitNativeTopAdWidget({
    super.key,
    required this.adCode,
    this.padding = EdgeInsets.zero,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_top';

  /// 스폰서줄 + 제목2줄 + 90dp 미디어 + 상하패딩 기준
  static const double slotHeight = 150;

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
    if (widget.adCode.isEmpty || _failed) return const SizedBox.shrink();

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
