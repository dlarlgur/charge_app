import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 리스트 인-피드 광고.
/// 레이아웃(adfit_native_list_row.xml)은 AdMob 리스트 카드와 동일 디자인 —
/// 높이는 호출측이 옆 스테이션 카드와 동일하게 지정(주유 68 / EV 96).
class AdFitNativeListAdWidget extends StatelessWidget {
  final String adCode;
  final double height;

  /// EV 탭 — 좌측 4dp 컬러 스트립 있는 레이아웃 사용.
  final bool isEv;

  const AdFitNativeListAdWidget({
    super.key,
    required this.adCode,
    this.height = 68,
    this.isEv = false,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_list';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) {
      return SizedBox(height: height);
    }
    if (adCode.isEmpty) {
      return SizedBox(height: height);
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: buildAdFitSurfaceAndroidView(
        viewType: _viewType,
        creationParams: <String, dynamic>{'clientId': adCode, 'isEv': isEv},
      ),
    );
  }
}
