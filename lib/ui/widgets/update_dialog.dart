import 'dart:io';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

class UpdateDialog extends StatefulWidget {
  final UpdatePolicy policy;

  const UpdateDialog({super.key, required this.policy});

  static Future<void> showIfNeeded(BuildContext context, UpdatePolicy policy) async {
    if (!policy.forceUpdate && !policy.optionalUpdate) return;

    if (policy.optionalUpdate && !policy.forceUpdate) {
      final box = Hive.box(AppConstants.settingsBox);
      final skipUntil = box.get('update_skip_until') as int?;
      if (skipUntil != null && DateTime.now().millisecondsSinceEpoch < skipUntil) {
        debugPrint('[UpdateDialog] 선택 업데이트 스킵 (${DateTime.fromMillisecondsSinceEpoch(skipUntil)}까지)');
        return;
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => UpdateDialog(policy: policy),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  int? _selectedSkipDays;

  Future<void> _openStore() async {
    final storeUrl = widget.policy.storeUrl;
    if (storeUrl != null && storeUrl.isNotEmpty) {
      final uri = Uri.parse(storeUrl);
      if (await canLaunchUrl(uri)) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (Platform.isAndroid) {
      final marketUri = Uri.parse('market://details?id=${AppConstants.packageName}');
      if (await canLaunchUrl(marketUri)) {
        launchUrl(marketUri, mode: LaunchMode.externalApplication);
        return;
      }
      final webUri = Uri.parse('https://play.google.com/store/apps/details?id=${AppConstants.packageName}');
      if (await canLaunchUrl(webUri)) launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  void _handleLater() {
    if (_selectedSkipDays != null) {
      final box = Hive.box(AppConstants.settingsBox);
      final skipUntil = DateTime.now().add(Duration(days: _selectedSkipDays!)).millisecondsSinceEpoch;
      box.put('update_skip_until', skipUntil);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isForced = widget.policy.forceUpdate;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final latestVersion = widget.policy.latestVersion ?? '';
    final releaseNote = widget.policy.releaseNote ?? '';
    final accent = isForced ? AppColors.error : AppColors.gasBlue;
    final accentDark = isForced ? const Color(0xFFB91C1C) : AppColors.gasBlueDark;

    final bg = isDark ? const Color(0xFF161B24) : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return PopScope(
      canPop: !isForced,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero header with gradient
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, accentDark],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isForced ? Icons.warning_amber_rounded : Icons.rocket_launch_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isForced ? '필수 업데이트' : '새 버전이 나왔어요',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${AppConstants.appName} $latestVersion',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.85),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (releaseNote.isNotEmpty) ...[
                        Text(
                          '변경 사항',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE8ECF0),
                            ),
                          ),
                          child: Text(
                            releaseNote,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: textPrimary,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                      if (isForced) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 15, color: textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '원활한 이용을 위해 최신 버전으로 업데이트해 주세요.',
                                style: TextStyle(fontSize: 12, color: textSecondary, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!isForced) ...[
                        const SizedBox(height: 16),
                        _SkipTile(
                          label: '하루 동안 보지 않기',
                          selected: _selectedSkipDays == 1,
                          accent: accent,
                          isDark: isDark,
                          onTap: () => setState(() => _selectedSkipDays = _selectedSkipDays == 1 ? null : 1),
                        ),
                        const SizedBox(height: 6),
                        _SkipTile(
                          label: '일주일 동안 보지 않기',
                          selected: _selectedSkipDays == 7,
                          accent: accent,
                          isDark: isDark,
                          onTap: () => setState(() => _selectedSkipDays = _selectedSkipDays == 7 ? null : 7),
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      if (!isForced) ...[
                        Expanded(
                          child: TextButton(
                            onPressed: _handleLater,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              '나중에',
                              style: TextStyle(
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        flex: isForced ? 1 : 2,
                        child: ElevatedButton(
                          onPressed: _openStore,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.download_rounded, size: 18),
                              SizedBox(width: 6),
                              Text(
                                '지금 업데이트',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipTile extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _SkipTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(isDark ? 0.15 : 0.08)
                : (isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFB)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.5)
                  : (isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE8ECF0)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: selected ? accent : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? accent
                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
