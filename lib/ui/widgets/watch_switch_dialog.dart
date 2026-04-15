import 'package:flutter/material.dart';

/// 자리 변동 알림 전환 확인 다이얼로그
/// returns true → 전환하기, false/null → 아니요
Future<bool> showWatchSwitchDialog(
  BuildContext context, {
  required String currentStationName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (ctx) => _WatchSwitchDialog(currentStationName: currentStationName),
  );
  return result == true;
}

class _WatchSwitchDialog extends StatelessWidget {
  final String currentStationName;
  const _WatchSwitchDialog({required this.currentStationName});

  static const _kBlue = Color(0xFF1D6FE0);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 52, height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF4FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, color: _kBlue, size: 26),
            ),
            const SizedBox(height: 16),

            // 타이틀
            const Text(
              '자리 변동 알림 전환',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),

            // 내용
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFF555555),
                ),
                children: [
                  TextSpan(
                    text: currentStationName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const TextSpan(text: '의 알림이 진행 중이에요.\n현재 알림을 끄고 이 충전소로 전환할까요?'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: Color(0xFFDDDDDD)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      '아니요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      '전환하기',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
