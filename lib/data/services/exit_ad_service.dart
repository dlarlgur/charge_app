import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/theme/app_colors.dart';
import 'ad_service.dart';

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

  // AdFit 앱 종료 팝업(전용 상품) 네이티브 채널 — MainActivity 에 등록됨.
  static const MethodChannel _adfitExit =
      MethodChannel('com.dksw.charge/adfit_exit');

  NativeAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  DateTime? _loadedAt; // 네이티브 광고 만료(~1시간) 판정용

  /// 광고 미리 로드 (앱 시작 시 1회 + 다이얼로그 소비 후 재호출).
  /// AdMob 모드 → AdMob 네이티브, AdFit 모드 → AdFit 종료 팝업(SDK 다이얼로그),
  /// off → 아무것도 로드하지 않음(다이얼로그는 광고 없이 컴팩트 표시).
  void preload() {
    final network = AdNetworkConfig.current;
    if (network == AdNetwork.adfit) {
      _adfitExit.invokeMethod('load', {'clientId': AdFitUnitIds.exit})
          .catchError((_) => null);
      return;
    }
    if (network != AdNetwork.admob) return;
    if (_ad != null || _loading) return;
    _loading = true;
    final ad = NativeAd(
      adUnitId: AdUnitIds.exitNative,
      request: const AdRequest(),
      // SDK 내장 미디엄 템플릿 — 'Ad' 어트리뷰션 배지 자동 포함(정책 요건).
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: AppColors.gasBlue, // 앱 브랜드 블루 (주황 X)
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
          _loadedAt = DateTime.now();
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

  /// 로드돼 있으면 광고를 **가져간다(소유권 이전)** — 반환 즉시 내부 참조를 비워
  /// 같은 광고가 두 다이얼로그에 동시에 붙는 걸 차단한다. 뒤로가기 연타로
  /// 다이얼로그가 겹치면 첫 쪽이 dispose 한 광고를 둘째 쪽이 그리려다
  /// "Ad with id could not be found" 빨간 에러 박스가 떴다(형 제보).
  /// 가져간 쪽이 노출 후 [recycle] 로 폐기+재로드까지 책임진다.
  NativeAd? takeIfLoaded() {
    if (!_loaded || _ad == null) return null;
    // 네이티브 광고는 ~1시간 뒤 만료 — 오래된 광고는 빈/에러 슬롯으로 뜨므로 버린다.
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) > const Duration(minutes: 50)) {
      _ad!.dispose();
      _ad = null;
      _loaded = false;
      _loading = false;
      preload();
      return null;
    }
    final ad = _ad;
    _ad = null;
    _loaded = false;
    _loading = false;
    return ad;
  }

  /// [takeIfLoaded] 로 가져간 광고를 노출 후 반납 — 폐기하고 다음 노출용 재로드.
  void recycle(NativeAd ad) {
    ad.dispose();
    preload();
  }

  /// AdFit 종료 팝업 표시 시도 (adfit 모드 전용).
  /// true = SDK 팝업이 종료 플로우를 처리함(종료 확정 시 여기서 앱 종료까지).
  /// false = 로드된 팝업 없음/오류 → 호출측이 기존 다이얼로그로 폴백.
  Future<bool> tryShowAdfitExitPopup() async {
    try {
      var res = await _adfitExit.invokeMethod<String>('show');
      if (res == 'none') {
        // preload 가 bootstrap(원격설정) 도착 전에 지나가 미로드일 수 있음 —
        // 즉석 로드(짧은 타임아웃) 후 1회만 재시도.
        final ok = await _adfitExit
            .invokeMethod<bool>('load', {'clientId': AdFitUnitIds.exit})
            .timeout(const Duration(milliseconds: 2500), onTimeout: () => false);
        if (ok == true) {
          res = await _adfitExit.invokeMethod<String>('show');
        }
      }
      if (res == 'exit') {
        await SystemNavigator.pop();
        return true;
      }
      if (res == 'dismiss') {
        preload(); // 다음 노출용 재로드
        return true;
      }
      return false; // 'none' — 미로드
    } catch (_) {
      return false;
    }
  }

}

// 다이얼로그 재진입 가드 — 뒤로가기 연타로 겹쳐 뜨는 것 자체를 막는다.
bool _exitDialogOpen = false;

/// 종료 확인 다이얼로그 — [취소] 는 닫기만, [종료] 는 앱 종료.
Future<void> showExitConfirmDialog(BuildContext context) async {
  if (_exitDialogOpen) return;
  _exitDialogOpen = true;
  try {
    await _showExitConfirmDialog(context);
  } finally {
    _exitDialogOpen = false;
  }
}

Future<void> _showExitConfirmDialog(BuildContext context) async {
  // AdFit 모드 — SDK 종료 팝업(광고+취소/앱 종료 버튼 일체형)이 플로우를 대신함.
  // 미로드/실패 시에만 아래 기본 다이얼로그(광고 없음)로 폴백.
  if (AdNetworkConfig.current == AdNetwork.adfit) {
    final handled = await ExitAdService.instance.tryShowAdfitExitPopup();
    if (handled) return;
    if (!context.mounted) return;
  }
  // preload 는 bootstrap(원격설정 수신) 전에 불릴 수 있어 노출 시점에 재확인 —
  // adfit/off 전환 시 미리 로드돼 있던 AdMob 광고가 새어 나가지 않게.
  final ad = AdNetworkConfig.current == AdNetwork.admob
      ? ExitAdService.instance.takeIfLoaded()
      : null;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A2E);
  final muted = isDark ? AppColors.darkTextMuted : const Color(0xFF94A3B8);

  // 미디엄 템플릿 필요 높이는 화면 '높이'가 아니라 다이얼로그 '폭'에 비례:
  // 미디어(폭×9/16) + 고정 행(아이콘·제목·본문·CTA ≈ 175dp).
  // → 폭 기반 계산이라 소형(320dp)~태블릿까지 잘림·과대 없이 스케일.
  //   (320 고정: 넓은 기기 CTA 잘림 / 410 고정: 좁은 기기 과대 — 실기기 피드백 이력)
  final screen = MediaQuery.of(context).size;
  // 태블릿에서 다이얼로그가 화면 전체로 퍼지지 않게 콘텐츠 폭 상한 420.
  final contentW = (screen.width - 48 /*insetPadding*/ - 40 /*내부 padding*/)
      .clamp(200.0, 420.0);
  final adHeight =
      (contentW * 9 / 16 + 175.0).clamp(280.0, screen.height * 0.55);

  final exit = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: isDark ? AppColors.darkSurface1 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        // 태블릿/폴더블 펼침에서도 폰 크기의 카드로 유지 (폭 상한 = 광고 높이 계산과 동일 기준)
        constraints: const BoxConstraints(maxWidth: 460),
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
                      child: AdWidget(key: GlobalObjectKey(ad), ad: ad),
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
                            backgroundColor: AppColors.gasBlueDark,
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
    ),
  );

  // 광고를 노출했으면(다이얼로그에 표시됨) 반납 — 폐기 + 다음 종료 시도용 재로드.
  if (ad != null) ExitAdService.instance.recycle(ad);
  if (exit == true) SystemNavigator.pop();
}
