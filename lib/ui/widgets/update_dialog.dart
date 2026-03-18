import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/version_service.dart';

class UpdateDialog extends StatefulWidget {
  final VersionCheckResult result;

  const UpdateDialog({super.key, required this.result});

  static Future<void> showIfNeeded(BuildContext context, VersionCheckResult result) async {
    if (result.type == UpdateType.none) return;

    // 선택 업데이트의 경우, 나중에 보기 설정 확인
    if (result.type == UpdateType.optional) {
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
      builder: (_) => UpdateDialog(result: result),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  int? _selectedSkipDays;

  Future<void> _openStore() async {
    if (Platform.isAndroid) {
      final marketUri = Uri.parse('market://details?id=${AppConstants.packageName}');
      if (await canLaunchUrl(marketUri)) {
        launchUrl(marketUri, mode: LaunchMode.externalApplication);
        return;
      }
      final webUri = Uri.parse('https://play.google.com/store/apps/details?id=${AppConstants.packageName}');
      if (await canLaunchUrl(webUri)) launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else if (Platform.isIOS) {
      const appStoreUrl = 'https://apps.apple.com/kr/app/id0000000000';
      final uri = Uri.parse(appStoreUrl);
      if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _handleLater() {
    if (_selectedSkipDays != null) {
      final box = Hive.box(AppConstants.settingsBox);
      final skipUntil = DateTime.now().add(Duration(days: _selectedSkipDays!)).millisecondsSinceEpoch;
      box.put('update_skip_until', skipUntil);
      debugPrint('[UpdateDialog] 업데이트 $_selectedSkipDays일 동안 스킵');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isForced = widget.result.type == UpdateType.forced;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !isForced,
      child: AlertDialog(
        backgroundColor: isDark ? AppColors.darkBg : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.system_update_rounded,
                color: isForced ? Colors.red : AppColors.gasBlue, size: 24),
            const SizedBox(width: 8),
            Text(
              isForced ? '필수 업데이트' : '새 버전 출시',
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppConstants.appName} ${widget.result.latestVersion}',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isForced ? Colors.red : AppColors.gasBlue,
              ),
            ),
            if (widget.result.releaseNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.result.releaseNote,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  height: 1.5,
                ),
              ),
            ],
            if (isForced) ...[
              const SizedBox(height: 10),
              Text(
                '현재 버전은 더 이상 지원되지 않습니다. 업데이트 후 이용해 주세요.',
                style: TextStyle(fontSize: 12, color: Colors.red.withOpacity(0.8)),
              ),
            ],
            if (!isForced) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                '나중에 업데이트',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _selectedSkipDays == 1,
                onChanged: (checked) {
                  setState(() {
                    _selectedSkipDays = checked == true ? 1 : null;
                  });
                },
                title: const Text('하루 동안 보지 않기', style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.gasBlue,
              ),
              CheckboxListTile(
                value: _selectedSkipDays == 7,
                onChanged: (checked) {
                  setState(() {
                    _selectedSkipDays = checked == true ? 7 : null;
                  });
                },
                title: const Text('일주일 동안 보지 않기', style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.gasBlue,
              ),
            ],
          ],
        ),
        actions: [
          if (!isForced)
            TextButton(
              onPressed: _handleLater,
              child: Text('나중에',
                  style: TextStyle(
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
            ),
          ElevatedButton(
            onPressed: _openStore,
            style: ElevatedButton.styleFrom(
              backgroundColor: isForced ? Colors.red : AppColors.gasBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('업데이트', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
