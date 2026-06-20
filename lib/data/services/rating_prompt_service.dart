import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/widgets/rating_dialog.dart';

/// 앱 진입 시 평점 안내 다이얼로그 노출 (하루 1회, 2번째 진입부터).
///
/// 흐름:
///  1. 첫 설치 직후 거부감 방지 — 2번째 진입부터 후보
///  2. 이미 평점했거나 오늘 이미 띄웠으면 스킵
///  3. RatingDialog("전기차 기름차가 마음에 드시나요?") 표시
///  4. 평점 남기기 → Google 인앱 리뷰 시트 → 무반응이면 Play Store 페이지 fallback
class RatingPromptService {
  static const String _keyRated = 'rating_rated';
  static const String _keyLastShownDate = 'rating_last_shown_date';
  static const String _keyEntryCount = 'rating_entry_count';
  static const int _minEntryCount = 2; // 2번째 진입부터 후보
  static const String _androidPackageId = 'com.dksw.charge';

  static final InAppReview _review = InAppReview.instance;

  static Future<bool> _shouldShowToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyRated) ?? false) return false;
      if (prefs.getString(_keyLastShownDate) == _todayString()) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 평점 안내 다이얼로그를 띄움. 안드로이드 외에는 no-op.
  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final entryCount = (prefs.getInt(_keyEntryCount) ?? 0) + 1;
    await prefs.setInt(_keyEntryCount, entryCount);
    if (entryCount < _minEntryCount) return;

    if (!await _shouldShowToday()) return;
    await prefs.setString(_keyLastShownDate, _todayString());
    if (!context.mounted) return;

    await RatingDialog.show(
      context: context,
      onConfirm: () async {
        await openReview();
        await _markRated();
      },
    );
  }

  /// 설정 "리뷰를 남겨주세요" 등에서 직접 호출 — 인앱 리뷰 시트 또는 스토어.
  static Future<void> openReview() async {
    if (kIsWeb || !Platform.isAndroid) {
      // iOS/웹 — 스토어 시도만.
      try {
        await _review.openStoreListing(appStoreId: _androidPackageId);
      } catch (_) {}
      return;
    }
    // 인앱 리뷰 시트 우선 → 1.5초 무반응이면 Play Store 페이지.
    final shown = Completer<bool>();
    final observer = _SheetShownObserver(() {
      if (!shown.isCompleted) shown.complete(true);
    });
    WidgetsBinding.instance.addObserver(observer);
    try {
      try {
        await _review.requestReview();
      } catch (_) {}
      final wasShown = await Future.any<bool>([
        shown.future,
        Future<bool>.delayed(const Duration(milliseconds: 1500), () => false),
      ]);
      if (wasShown) return;
      try {
        await _review.openStoreListing(appStoreId: _androidPackageId);
      } catch (_) {}
    } finally {
      WidgetsBinding.instance.removeObserver(observer);
    }
  }

  static Future<void> _markRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRated, true);
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

/// 인앱 리뷰 시트가 떴는지(앱 paused/inactive) 감지하는 짧은 수명 옵저버.
class _SheetShownObserver with WidgetsBindingObserver {
  final VoidCallback onShown;
  _SheetShownObserver(this.onShown);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      onShown();
    }
  }
}
