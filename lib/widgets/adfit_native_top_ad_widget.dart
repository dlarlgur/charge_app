import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adfit_android_view_surface.dart';

/// Kakao AdFit 네이티브 상단/상세 카드 (2단 카드 스타일).
///
/// 단순 표시만 — 로드/실패 판정은 네이티브 팩토리가 XML placeholder 로 처리.
/// (이전에 실패 시 자리접기 로직을 넣었다가 순간 no-fill 에도 배너가 사라지는
///  회귀가 있어 제거. 폭은 XML 패딩을 없애고 여기 [padding] 으로만 준다.)
class AdFitNativeTopAdWidget extends StatelessWidget {
  final String adCode;

  /// 바깥 여백 — AdMob 상단 카드와 동일하게 좌우 16 (XML 에는 패딩 없음).
  final EdgeInsets padding;

  const AdFitNativeTopAdWidget({
    super.key,
    required this.adCode,
    this.padding = EdgeInsets.zero,
  });

  static const String _viewType = 'com.dksw.charge/adfit_native_top';

  /// 스폰서줄 + 제목2줄 + 90dp 미디어 + 내부패딩 기준 (XML 루트 패딩 제거 후 실측)
  static const double slotHeight = 144;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) return const SizedBox.shrink();
    if (adCode.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: double.infinity,
          height: slotHeight,
          child: buildAdFitSurfaceAndroidView(
            viewType: _viewType,
            creationParams: <String, dynamic>{'clientId': adCode},
          ),
        ),
      ),
    );
  }
}
