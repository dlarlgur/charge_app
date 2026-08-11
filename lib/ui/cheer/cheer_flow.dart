import 'package:flutter/material.dart';

import '../../core/util/app_toast.dart';
import '../../data/services/cheer_service.dart';
import 'cheer_tier_theme.dart';
import 'garage_screen.dart';
import 'promotion_overlay.dart';
import 'thanks_sheet.dart';

/// 보상형 광고 시청 → 적립 → (승급이면 승급 오버레이 / 아니면 감사 바텀시트) 공용 플로우.
/// 응원 화면과 개러지(등급 팝업 CTA — 형 확정: 그 자리에서 바로 광고) 두 곳에서 쓴다.
///
/// [onStatus] — 적립 후 최신 상태를 호출부 화면에 반영 (setState).
/// 반환: 광고를 실제로 띄웠으면 true (준비 안 됐으면 false — 호출부가 로딩 처리).
Future<bool> runCheerAdFlow(
  BuildContext context, {
  required void Function(CheerStatus st) onStatus,
  /// 감사 시트·승급 오버레이를 닫은 뒤 호출 — 응원 화면의 하트 비행 연출용.
  void Function(CheerStatus st)? onCelebrationClosed,
}) async {
  final svc = CheerService.instance;
  if (!svc.adReady) {
    // 감사시트 '한 번 더'·개러지 팝업 CTA 처럼 로드 전에 누르는 경로 — 무반응이면
    // 고장으로 보인다. 로드를 걸고 짧게 안내한다.
    svc.preload();
    if (context.mounted) {
      showAppToast(context, '광고를 준비하고 있어요. 잠시 후 다시 눌러주세요');
    }
    return false;
  }

  final levelBefore =
      CheerTierTheme.of(svc.cachedTotal)?.level ?? 0;
  CheerStatus? earnedStatus;

  await svc.show(
    onEarned: () async {
      final st = await svc.cheer();
      if (st != null) {
        earnedStatus = st;
        onStatus(st);
      }
    },
    onDismissed: () {
      // 광고가 닫힌 다음에 연출 — 광고 위에서는 아무것도 안 보인다.
      final st = earnedStatus;
      if (st == null || !context.mounted) return;
      if (!st.doneToday) {
        svc.preload();
      }
      final tier = CheerTierTheme.of(st.total);
      if (tier != null && tier.level > levelBefore) {
        // 승급 — 감사 시트 대신 승급 오버레이 우선 (핸드오프 스펙).
        showCheerPromotionOverlay(context, tier: tier, status: st,
            onSeeGarage: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GarageScreen(initialStatus: st)));
        }).then((_) => onCelebrationClosed?.call(st));
      } else {
        showCheerThanksSheet(context, status: st, onStatus: onStatus,
            onAgain: () {
          // 시트 pop → ⚡ 연출(620ms)이 먼저 재생되고, 끝날 즈음 다음 광고.
          Future.delayed(const Duration(milliseconds: 800), () {
            if (context.mounted) {
              runCheerAdFlow(context,
                  onStatus: onStatus,
                  onCelebrationClosed: onCelebrationClosed);
            }
          });
        }).then((_) => onCelebrationClosed?.call(st));
      }
    },
  );
  return true;
}
