import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 상단 카드 (홈 탭 탭바 아래 배너 스타일)
class AdFitNativeTopAdWidget extends StatelessWidget {
  final String adCode;

  const AdFitNativeTopAdWidget({
    super.key,
    required this.adCode,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_top';

  /// 스폰서줄 + 제목2줄 + 90dp 미디어 + 상하패딩 기준
  static const double slotHeight = 150;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) {
      return const SizedBox(height: slotHeight);
    }
    if (adCode.isEmpty) {
      return const SizedBox(height: slotHeight);
    }

    return SizedBox(
      width: double.infinity,
      height: slotHeight,
      child: buildAdFitSurfaceAndroidView(
        viewType: _viewType,
        creationParams: <String, dynamic>{'clientId': adCode},
      ),
    );
  }
}
