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
  // 보더: 흰색 14% 알파 (이전 8% → 14%, 카드 경계 명확)
  static const darkCardBorder = Color(0x24FFFFFF);
  static const darkTextPrimary = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkTextMuted = Color(0xFF475569);
  static const darkIconBg = Color(0xFF1E293B);
  static const darkEvIconBg = Color(0xFF064E3B);

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

  // ─── Common ───
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const divider = Color(0x26808080);
}
