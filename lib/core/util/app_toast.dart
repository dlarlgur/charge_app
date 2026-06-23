import 'package:flutter/material.dart';

/// 짧고 이쁜 토스트 — 기본 `showSnackBar`(4초·검정) 대체.
/// 모양은 ThemeData.snackBarTheme(둥근 플로팅 슬레이트)을 따르고, 여기선 길이만 짧게(2.2초)+
/// 이전 토스트 즉시 치우고 새로 띄움(쌓임·길게 남는 것 방지).
void showAppToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, textAlign: TextAlign.center),
      duration: const Duration(milliseconds: 2200),
      backgroundColor: isError ? const Color(0xFF8A2E2E) : null,
    ),
  );
}
