import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/widgets/rating_dialog.dart';

/// 평점 안내 — 만족도 게이트 + 백오프 + 평생 캡.
///
/// 흐름:
///  1. 2번째 진입부터 후보, 이미 평점했으면 영구 중단.
///  2. 만족도 게이트: 👍 → 스토어 별점(만족 유저만 공개로 유도) /
///     👎 → 1:1 문의(불만은 비공개로 수집 → 공개 별점 방어).
///  3. 무시하면 7→30일 백오프 + 평생 3회까지만(나깅 방지).
///  4. 최근 부정 경험(에러/검색0건) 직후면 그 24시간은 스킵.
class RatingPromptService {
  static const String _keyRated = 'rating_rated';
  static const String _keyEntryCount = 'rating_entry_count';
  static const String _keyPromptCount = 'rating_prompt_count';
  static const String _keyLastPromptTs = 'rating_last_prompt_ts';
  static const String _keyNegativeUntil = 'rating_negative_until';

  static const int _minEntryCount = 2; // 2번째 진입부터 후보
  static const int _maxPrompts = 3; // 평생 노출 캡
  static const String _androidPackageId = 'com.dksw.charge';

  static final InAppReview _review = InAppReview.instance;

  /// 에러·검색 0건 등 부정 경험 시 호출 → 24시간 동안 평점 안내 스킵.
  /// (짜증난 순간에 별점 물어 역효과 나는 것 방지)
  static Future<void> markNegativeSignal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = DateTime.now()
          .add(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      await prefs.setInt(_keyNegativeUntil, until);
    } catch (_) {}
  }

  /// 평점 안내 다이얼로그를 띄움. 안드로이드 외에는 no-op.
  ///
  /// [onNegativeFeedback] : 👎(아쉬워요) 선택 시 호출 — 1:1 문의 화면으로
  /// 이동시키는 콜백(라우팅은 호출부가 담당).
  static Future<void> maybeShow(
    BuildContext context, {
    required VoidCallback onNegativeFeedback,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();

    // 진입 카운트(첫 설치 직후 거부감 방지 — 2번째 진입부터)
    final entryCount = (prefs.getInt(_keyEntryCount) ?? 0) + 1;
    await prefs.setInt(_keyEntryCount, entryCount);
    if (entryCount < _minEntryCount) return;

    if (!await _eligible(prefs)) return;

    // 노출 확정 — 카운트/시각 기록(백오프·캡 기준)
    final promptCount = prefs.getInt(_keyPromptCount) ?? 0;
    await prefs.setInt(_keyPromptCount, promptCount + 1);
    await prefs.setInt(
        _keyLastPromptTs, DateTime.now().millisecondsSinceEpoch);
    if (!context.mounted) return;

    await RatingDialog.show(
      context: context,
      onPositive: () async {
        // 👍 만족 → 스토어 별점(만족 유저만 공개로) → 영구 중단
        await openReview();
        await _markRated();
      },
      onNegative: onNegativeFeedback, // 👎 불만 → 1:1 문의(비공개 수집)
    );
  }

  /// 노출 자격 판단 — 평점완료/캡/부정신호/백오프.
  static Future<bool> _eligible(SharedPreferences prefs) async {
    // 이미 평점 → 영구 중단
    if (prefs.getBool(_keyRated) ?? false) return false;

    // 평생 노출 캡(3회 노출하면 그만 — 나깅 방지)
    final promptCount = prefs.getInt(_keyPromptCount) ?? 0;
    if (promptCount >= _maxPrompts) return false;

    // 최근 부정 경험 직후(24h)면 스킵
    final negUntil = prefs.getInt(_keyNegativeUntil) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < negUntil) return false;

    // 백오프: 0회→바로, 1회→7일, 2회→30일 간격 필요
    final backoffDays = promptCount == 0 ? 0 : (promptCount == 1 ? 7 : 30);
    if (backoffDays > 0) {
      final lastTs = prefs.getInt(_keyLastPromptTs) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
      if (elapsed < backoffDays * 86400000) return false;
    }
    return true;
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
