import 'package:flutter/material.dart';

import '../../core/util/app_toast.dart';
import '../../data/services/cheer_service.dart';
import 'car_paint.dart';
import 'car_paint_screen.dart';
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
  /// 감사 시트·승급 오버레이를 닫은 뒤 호출 — 응원 화면의 리워드 연출용.
  void Function(CheerStatus st)? onCelebrationClosed,
  /// 응원 메인 화면에서 호출할 때 true — handoff 2 부터 감사 바텀시트 대신
  /// 화면 안에서 리워드 연출(오브 비행 → 차 히트 → 게이지 상승)이 재생된다.
  /// 개러지 등 연출을 못 그리는 화면은 false 로 감사 시트를 그대로 쓴다.
  bool inlineReward = false,
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

  final totalBefore = svc.cachedTotal; // 적립 실패 시 '실제로 올랐는지' 판정 기준
  final levelBefore =
      CheerTierTheme.of(svc.cachedTotal)?.level ?? 0;
  CheerStatus? earnedStatus;
  Future<void>? earning;

  await svc.show(
    onEarned: () {
      earning = () async {
        final st = await svc.cheer();
        if (st != null) {
          earnedStatus = st;
          onStatus(st);
        }
      }();
    },
    onDismissed: () async {
      // 광고가 닫힌 다음에 연출 — 광고 위에서는 아무것도 안 보인다.
      // 보상 콜백은 광고가 닫히기 직전에 오므로, 닫힘 시점엔 적립 API 가
      // 아직 응답 전일 수 있다. 기다리지 않으면 연출이 통째로 건너뛰어진다.
      if (earning != null) {
        try {
          await earning!.timeout(const Duration(seconds: 8));
        } catch (_) {}
      }

      // 적립 응답을 못 받은 경우 — 광고는 이미 끝까지 봤다. 그냥 return 하면
      // 토스트도 게이지 변화도 없이 아무 일 없던 게 되어 고장으로 보인다.
      //
      // 여기서 POST 를 재시도하면 안 된다. 실패 원인이 '기록은 됐는데 응답이 깨진'
      // 경우(예: INSERT 후 상태 조회 실패)일 수 있어 중복 적립이 된다.
      // 대신 상태를 다시 읽어 실제로 올랐는지 본다 — 올랐으면 정상 연출로 이어간다.
      if (earnedStatus == null && earning != null && context.mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        final recovered = await svc.status();
        if (recovered != null && recovered.total > totalBefore) {
          earnedStatus = recovered;
          onStatus(recovered);
        }
      }

      final st = earnedStatus;
      if (!context.mounted) return;
      if (st == null) {
        // 여기 와도 응원은 유실되지 않는다 — cheer() 가 client_key 를 큐에 넣어뒀고
        // 다음 preload/status 에서 자동 재전송, 서버가 dedupe 한다(형 지시: 광고를
        // 다 봤으면 무조건 쳐준다). 그러니 '실패'가 아니라 '접수'로 말한다.
        svc.preload();
        showAppToast(context, '응원 고마워요! 연결이 고르지 않아 잠시 후 자동 반영돼요');
        return;
      }
      if (!st.doneToday) {
        svc.preload();
      }
      final tier = CheerTierTheme.of(st.total);
      if (tier != null && tier.level > levelBefore) {
        // 승급 — 감사 시트 대신 승급 오버레이 우선 (핸드오프 스펙).
        showCheerPromotionOverlay(
          context,
          tier: tier,
          status: st,
          onSeeGarage: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GarageScreen(initialStatus: st)));
          },
          // 승급 보상 컬러가 열렸으면 그 자리에서 바로 입혀볼 수 있게 — 여기서
          // 안내하지 않으면 유광 3색은 아무도 모르고 지나간다.
          onOpenPaint: () {
            CarPaintService.instance.markCoachSeen();
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    CarPaintScreen(tier: tier, total: st.total)));
          },
        ).then((_) => onCelebrationClosed?.call(st));
      } else if (inlineReward) {
        // 팝업 없이 바로 화면 연출 — 시안의 '광고 닫힘 직후 메인 화면' 흐름.
        onCelebrationClosed?.call(st);
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
