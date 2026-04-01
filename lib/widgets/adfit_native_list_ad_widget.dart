import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 목록 슬롯 (주유소/충전소 리스트 3번째 위치 삽입용)
class AdFitNativeListAdWidget extends StatelessWidget {
  final String adCode;

  const AdFitNativeListAdWidget({
    super.key,
    required this.adCode,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_list';

  /// 광고 슬롯 고정 높이 (아이콘 44dp + 상하 패딩)
  static const double slotHeight = 84;

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
