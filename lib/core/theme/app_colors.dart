import 'package:flutter/material.dart';

/// 앱 전체 컬러 시스템
/// 주유 = Blue / 충전 = Green 으로 탭별 분리
class AppColors {
  AppColors._();

  // ─── Brand ───
  static const gasBlue = Color(0xFF3B82F6);
  static const gasBlueDark = Color(0xFF2563EB);
  static const evGreen = Color(0xFF10B981);
  static const evGreenDark = Color(0xFF059669);

  // ─── Dark Theme ───
  static const darkBg = Color(0xFF0C0E13);
  // 카드: 흰색 7% 알파 (이전 3% → 7% 로 살짝 lift, OLED 가독성 ↑)
  static const darkCard = Color(0x12FFFFFF);
  // 지도 위 오버레이 카드 — 반투명 darkCard 는 지도가 비쳐 묻히므로 '불투명' 색 사용.
  static const darkMapOverlay = Color(0xFF1A1F2A);
  // 보더: 흰색 14% 알파 (이전 8% → 14%, 카드 경계 명확)
  static const darkCardBorder = Color(0x24FFFFFF);
  static const darkTextPrimary = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  // muted: #475569 는 darkBg 위 대비 ~2.4:1 로 캡션이 안 읽혔음 → ~4.6:1 로 상향
  static const darkTextMuted = Color(0xFF7E8CA0);
  static const darkIconBg = Color(0xFF1E293B);
  static const darkEvIconBg = Color(0xFF064E3B);

  // ─── Dark surface 사다리 (반투명 스택 대신 불투명 계층) ───
  // 시트(darkBg) → 카드(surface1) → 카드 내 수치셀(surface2) — 밝기 1단계씩 상승.
  static const darkSurface1 = Color(0xFF171E27);
  static const darkSurface2 = Color(0xFF212A35);

  // ─── Dark 전용 밝은 accent 변형 (라이트 원색은 다크에서 대비 미달) ───
  static const darkOrangeBright = Color(0xFFFFA14E); // ← #E8700A
  static const darkBlueBright = Color(0xFF6EA8FF); //   ← #1D6FE0
  static const darkGreenBright = Color(0xFF3ECF9A); //  ← #1D9E75
  static const darkRedBright = Color(0xFFFF7A76); //    ← #E24B4A/#DC2626
  static const darkAmberBright = Color(0xFFEDC65A); //  ← 앰버 안내배너 텍스트

  // Gas active card (dark)
  static const darkGasActiveCard = Color(0x12397CF6);
  static const darkGasActiveBorder = Color(0x2E3B82F6);
  // EV active card (dark)
  static const darkEvActiveCard = Color(0x1210B981);
  static const darkEvActiveBorder = Color(0x2E10B981);

  // ─── Light Theme ───
  static const lightBg = Color(0xFFF8FAFB);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCardBorder = Color(0xFFE8ECF0);
  static const lightTextPrimary = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF64748B);
  static const lightTextMuted = Color(0xFF94A3B8);
  static const lightIconBg = Color(0xFFF1F5F9);
  static const lightEvIconBg = Color(0xFFECFDF5);

  // 로그인 히어로(순백 미니멀 3a) — 상단 순백에서 하단 옅은 청록으로 떨어지는 배경.
  // 일반 화면 배경(lightBg)보다 밝아야 글로우 2개가 살아난다.
  static const loginHeroTop = Color(0xFFFFFFFF);
  static const loginHeroBottom = Color(0xFFF7FBFA);

  // Gas active card (light)
  static const lightGasActiveCard = Color(0xFFEFF6FF);
  static const lightGasActiveBorder = Color(0xFFBFDBFE);
  // EV active card (light)
  static const lightEvActiveCard = Color(0xFFECFDF5);
  static const lightEvActiveBorder = Color(0xFFA7F3D0);

  // ─── Status Badges ───
  static const statusAvailable = Color(0xFF10B981);
  static const statusCharging = Color(0xFFF59E0B);
  static const statusOffline = Color(0xFFEF4444);
  static const statusFast = Color(0xFF60A5FA);

  // Badge backgrounds (dark)
  static const darkBadgeAvailBg = Color(0x2610B981);
  static const darkBadgeChargingBg = Color(0x26F59E0B);
  static const darkBadgeOfflineBg = Color(0x26EF4444);
  static const darkBadgeFastBg = Color(0x1F3B82F6);

  // Badge backgrounds (light)
  static const lightBadgeAvailBg = Color(0xFFD1FAE5);
  static const lightBadgeChargingBg = Color(0xFFFEF3C7);
  static const lightBadgeOfflineBg = Color(0xFFFEE2E2);
  static const lightBadgeFastBg = Color(0xFFDBEAFE);

  // ─── Gradients ───
  static const gasSummaryGradientDark = [Color(0xFF162032), Color(0xFF111827)];
  static const gasSummaryGradientLight = [Color(0xFFEFF6FF), Color(0xFFDBEAFE)];
  static const evSummaryGradientDark = [Color(0xFF064E3B), Color(0xFF111827)];
  static const evSummaryGradientLight = [Color(0xFFECFDF5), Color(0xFFD1FAE5)];
  static const logoGradient = [Color(0xFF2563EB), Color(0xFF10B981)];

  // ─── 응원(cheer) 골드 ───
  // 모드색(파랑/초록)과 겹치지 않아야 스트립이 눈에 띈다 — 두 탭 모두 동일 색.
  static const supportAccent = Color(0xFFF59E0B);
  static const supportBgLight = Color(0xFFFEF3C7);
  static const supportTextLight = Color(0xFFB45309);
  // 다크: 라이트 원색(#FEF3C7 배경 / #B45309 글자)은 다크 배경에서 대비가 뒤집힌다.
  static const supportBgDark = Color(0x1FF59E0B);
  static const supportTextDark = Color(0xFFEDC65A);

  // ─── Common ───
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const divider = Color(0x26808080);
}
