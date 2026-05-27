import 'package:flutter/material.dart';

const kPrimary = Color(0xFF1D9E75);
const kPrimaryLight = Color(0xFFE1F5EE);
const kDanger = Color(0xFFE24B4A);

// 사용자 선택 모드(A/B) 색상
const kCompareBlue = Color(0xFF1D6FE0);

// ─── 모드별 액센트 컬러 ───
// 앱 전체 컨벤션과 통일: AppColors.gasBlue (주유) / AppColors.evGreen (충전)
// (값은 compile-time const 유지 위해 같은 RGB 그대로 복사)
const kFuelAccent = Color(0xFF3B82F6);      // = AppColors.gasBlue
const kFuelAccentLight = Color(0xFFEFF6FF);
const kEvAccent = Color(0xFF10B981);        // = AppColors.evGreen
const kEvAccentLight = Color(0xFFECFDF5);
// ai_reco_main.html 그라데이션 — primary gradient end (toggle/CTA 진한 톤)
const kFuelAccentDeep = Color(0xFF2563EB);
const kEvAccentDeep = Color(0xFF059669);
Color modeAccentDeep(bool isEv) => isEv ? kEvAccentDeep : kFuelAccentDeep;
// ai_reco_main.html 디자인 토큰 — ink/muted/line/bg 통일
const kInk = Color(0xFF0F172A);
const kInk2 = Color(0xFF334155);
const kMuted = Color(0xFF64748B);
const kMute2 = Color(0xFF94A3B8);
const kLine = Color(0xFFE2E8F0);
const kLineSoft = Color(0xFFF1F5F9);

Color modeAccent(bool isEv) => isEv ? kEvAccent : kFuelAccent;
Color modeAccentLight(bool isEv) => isEv ? kEvAccentLight : kFuelAccentLight;
