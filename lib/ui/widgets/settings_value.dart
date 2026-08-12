import 'package:flutter/material.dart';

/// 설정 행(ListTile)의 값 텍스트 — 폭 상한 + 1줄 말줄임.
///
/// ListTile 은 leading·trailing 을 먼저 배치하고 **남은 폭만** title 에 준다.
/// 그래서 값이 길면 타이틀이 0 폭까지 밀려 '광/고/문/의' 처럼 한 글자씩 세로로
/// 쪼개진다(형 제보 2026-08-12). 값에 상한을 걸어 타이틀 자리를 항상 남긴다.
///
/// 설정 화면이 두 벌(홈 탭의 `SettingsScreenEmbed`, 구 `SettingsScreen`)이라
/// 규칙을 여기 한 곳에만 둔다 — 상한을 조정할 때 한쪽만 바뀌면 안 된다.
class SettingsValue extends StatelessWidget {
  /// 값이 가져갈 수 있는 최대 폭 (화면 폭 대비)
  static const maxWidthRatio = 0.34;

  final String value;
  final Color? color;
  final TextStyle? style;

  const SettingsValue(this.value, {super.key, this.color, this.style});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * maxWidthRatio),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: color == null ? base : base?.copyWith(color: color),
      ),
    );
  }
}
