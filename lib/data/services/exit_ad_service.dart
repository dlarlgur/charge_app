import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/theme/app_colors.dart';

/// 앱 종료 확인 다이얼로그 + 네이티브 광고.
///
/// 이전엔 종료 직전 전면(Interstitial)을 띄웠으나 AdMob 비허용 배치
/// ("앱 종료 시 전면광고")라 게재 제한 리스크 → 종료 확인 다이얼로그 안에
/// 네이티브 광고를 넣는 허용 패턴으로 전환.
///  · 광고 표기: SDK 내장 템플릿(NativeTemplateStyle)이 'Ad' 배지를 자동 렌더.
///  · 오클릭 방지: 광고 영역과 종료/취소 버튼 사이 20dp 여백.
///  · 레이아웃: 템플릿이 주어진 높이에 맞춰 스케일 — 잘림 없음. 광고 미로드 시
///    광고 없이 컴팩트 다이얼로그로 표시(종료를 막지 않음).
class ExitAdService {
  ExitAdService._();
  static final ExitAdService instance = ExitAdService._();

  // 종료 다이얼로그 전용 네이티브 단위 (신규 발급분 — 게재 시작까지 최대 1시간 걸릴 수 있음).
  static const String _adUnitId = 'ca-app-pub-8640148276009977/4895744199';

  NativeAd? _ad;
  bool _loaded = false;
  bool _loading = false;

  /// 네이티브 광고 미리 로드 (앱 시작 시 1회 + 다이얼로그 소비 후 재호출).
  void preload() {
    if (_ad != null || _loading) return;
    _loading = true;
    final ad = NativeAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      // SDK 내장 미디엄 템플릿 — 'Ad' 어트리뷰션 배지 자동 포함(정책 요건).
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFFE8700A),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF1A1A2E),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF64748B),
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _loaded = true;
          _loading = false;
        },
        onAdFailedToLoad: (ad, error) {
          if (kDebugMode) {
            debugPrint('[ExitAd] native load 실패: ${error.message}');
          }
          ad.dispose();
          _ad = null;
          _loaded = false;
          _loading = false;
        },
      ),
    );
    _ad = ad;
    _loaded = false;
    ad.load();
  }

  NativeAd? takeIfLoaded() => _loaded ? _ad : null;

  /// 다이얼로그에서 광고를 소비(노출)한 뒤 호출 — 폐기하고 다음 노출용 재로드.
  void consumeAndReload() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    _loading = false;
    preload();
  }
}

/// 종료 확인 다이얼로그 — [취소] 는 닫기만, [종료] 는 앱 종료.
Future<void> showExitConfirmDialog(BuildContext context) async {
  final ad = ExitAdService.instance.takeIfLoaded();
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
  final muted = isDark ? AppColors.darkTextMuted : const Color(0xFF94A3B8);

  // 미디엄 템플릿 권장 높이 320dp — 소형 화면에선 화면의 40%까지로 클램프(잘림 방지).
  final adHeight =
      (MediaQuery.of(context).size.height * 0.40).clamp(250.0, 320.0);

  final exit = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('앱을 종료할까요?',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 5),
              Text('다음에 또 만나요',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              if (ad != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: adHeight,
                    width: double.infinity,
                    child: AdWidget(ad: ad),
                  ),
                ),
              ],
              // 광고와 버튼 사이 여백 — 오클릭(의도치 않은 광고 클릭) 방지, 정책 요건.
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: isDark
                                  ? AppColors.darkCardBorder
                                  : const Color(0xFFD8DEE6)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('취소',
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: ink)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8700A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('종료',
                            style: TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // 광고를 노출했으면(다이얼로그에 표시됨) 소비 처리 — 다음 종료 시도용 재로드.
  if (ad != null) ExitAdService.instance.consumeAndReload();
  if (exit == true) SystemNavigator.pop();
}
