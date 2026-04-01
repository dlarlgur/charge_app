import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/version_service.dart';
import '../../data/services/alert_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(context, '차량 설정'),
          _settingTile(context, isDark,
            icon: Icons.directions_car_rounded,
            title: '차량 타입',
            value: settings.vehicleType.label,
            onTap: () => _showVehicleTypePicker(context, ref),
          ),
          if (settings.vehicleType != VehicleType.ev)
            _settingTile(context, isDark,
              icon: Icons.local_gas_station_rounded,
              title: '유종',
              value: settings.fuelType.label,
              onTap: () => _showFuelTypePicker(context, ref),
            ),
          if (settings.vehicleType != VehicleType.gas)
            _settingTile(context, isDark,
              icon: Icons.ev_station_rounded,
              title: '충전기 타입',
              value: settings.chargerTypes.isEmpty
                  ? '미선택'
                  : '${settings.chargerTypes.length}개 선택',
              onTap: () => _showChargerTypePicker(context, ref),
            ),
          _settingTile(context, isDark,
            icon: Icons.radar_rounded,
            title: '검색 반경',
            value: '${(settings.radius / 1000).toInt()}Km',
            onTap: () => _showRadiusPicker(context, ref),
          ),

          const SizedBox(height: 16),
          _sectionHeader(context, '알림'),
          _AlertSettingTile(isDark: isDark),

          const SizedBox(height: 16),
          _sectionHeader(context, '앱 설정'),
          _settingTile(context, isDark,
            icon: Icons.dark_mode_rounded,
            title: '테마',
            value: themeMode == ThemeMode.dark ? '다크' : '라이트',
            onTap: () => _showThemePicker(context, ref),
          ),

          const SizedBox(height: 16),
          _sectionHeader(context, '정보'),
          FutureBuilder<String>(
            future: VersionService.fetchLatestVersion(),
            builder: (context, snap) => _settingTile(context, isDark,
                icon: Icons.info_outline_rounded, title: '앱 버전', value: snap.data ?? '...'),
          ),
          _settingTile(context, isDark, icon: Icons.description_outlined, title: '이용약관', onTap: () {}),
          _settingTile(context, isDark, icon: Icons.shield_outlined, title: '개인정보 처리방침', onTap: () {}),

          const SizedBox(height: 24),

          // 데이터 출처
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Text(
              '유가 정보 출처: 한국석유공사 오피넷(www.opinet.co.kr)\n충전소 정보 출처: 환경부 전기차 충전소 공공데이터',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.gasBlue, letterSpacing: 0.3)),
    );
  }

  Widget _settingTile(BuildContext context, bool isDark, {
    required IconData icon, required String title, String? value, VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 22, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) Text(value, style: Theme.of(context).textTheme.bodyMedium),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  void _showVehicleTypePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Text('차량 타입', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...VehicleType.values.map((t) => ListTile(
          title: Text(t.label),
          trailing: ref.read(settingsProvider).vehicleType == t ? const Icon(Icons.check, color: AppColors.gasBlue) : null,
          onTap: () { ref.read(settingsProvider.notifier).setVehicleType(t); Navigator.pop(context); },
        )),
        const SizedBox(height: 16),
      ]),
    ));
  }

  void _showFuelTypePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Text('유종 선택', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...FuelType.values.map((t) => ListTile(
          title: Text(t.label),
          trailing: ref.read(settingsProvider).fuelType == t ? const Icon(Icons.check, color: AppColors.gasBlue) : null,
          onTap: () { ref.read(settingsProvider.notifier).setFuelType(t); Navigator.pop(context); },
        )),
        const SizedBox(height: 16),
      ]),
    ));
  }

  void _showChargerTypePicker(BuildContext context, WidgetRef ref) {
    final types = [
      ('02', 'AC완속'),
      ('07', 'AC3상'),
      ('04', 'DC콤보'),
      ('01', 'DC차데모'),
      ('09', 'NACS'),
      ('SC', '슈퍼차저'),
      ('DT', '데스티네이션'),
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) {
          final selected = List<String>.from(ref.read(settingsProvider).chargerTypes);
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              Text('충전기 타입', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...types.map((t) {
                final isSelected = selected.contains(t.$1);
                return ListTile(
                  title: Text(t.$2),
                  trailing: isSelected
                      ? const Icon(Icons.check_box_rounded, color: AppColors.evGreen)
                      : const Icon(Icons.check_box_outline_blank_rounded),
                  onTap: () {
                    setState(() {
                      if (isSelected) selected.remove(t.$1);
                      else selected.add(t.$1);
                    });
                    ref.read(settingsProvider.notifier).setChargerTypes(List.from(selected));
                  },
                );
              }),
              const SizedBox(height: 16),
            ]),
          );
        },
      ),
    );
  }

  void _showRadiusPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Text('검색 반경', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...AppConstants.radiusOptions.map((r) => ListTile(
          title: Text('${(r / 1000).toInt()}Km'),
          trailing: ref.read(settingsProvider).radius == r ? const Icon(Icons.check, color: AppColors.gasBlue) : null,
          onTap: () { ref.read(settingsProvider.notifier).setRadius(r); Navigator.pop(context); },
        )),
        const SizedBox(height: 16),
      ]),
    ));
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Text('테마', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...[ThemeMode.light, ThemeMode.dark].map((m) => ListTile(
          title: Text(m == ThemeMode.dark ? '다크 모드' : '라이트 모드'),
          trailing: ref.read(themeModeProvider) == m ? const Icon(Icons.check, color: AppColors.gasBlue) : null,
          onTap: () { ref.read(themeModeProvider.notifier).setTheme(m); Navigator.pop(context); },
        )),
        const SizedBox(height: 16),
      ]),
    ));
  }
}

class _AlertSettingTile extends StatefulWidget {
  final bool isDark;
  const _AlertSettingTile({required this.isDark});
  @override
  State<_AlertSettingTile> createState() => _AlertSettingTileState();
}

class _AlertSettingTileState extends State<_AlertSettingTile> {
  late bool _enabled;
  late List<String> _ids;
  late int _alertHour;
  late int _alertMinute;
  bool _expanded = false;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _enabled = AlertService().alertsEnabled;
    _ids = AlertService().subscribedStationIds;
    _alertHour = AlertService().alertHour;
    _alertMinute = AlertService().alertMinute;
  }

  Future<void> _pickAlertTime() async {
    final picked = await showDrumTimePicker(
      context,
      initial: TimeOfDay(hour: _alertHour, minute: _alertMinute),
    );
    if (picked == null || !mounted) return;
    await AlertService().setAlertTime(picked.hour, picked.minute);
    setState(() {
      _alertHour = picked.hour;
      _alertMinute = picked.minute;
    });
  }

  String get _alertTimeText =>
      '${_alertHour.toString().padLeft(2, '0')}:${_alertMinute.toString().padLeft(2, '0')}';

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final status = await Permission.notification.status;
      if (status.isPermanentlyDenied) {
        // 이미 영구 거부 → 설정으로 안내
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('알림 권한 필요'),
            content: const Text('기기 설정에서 알림을 허용해주세요.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
              TextButton(
                onPressed: () { Navigator.pop(ctx); openAppSettings(); },
                child: const Text('설정 열기', style: TextStyle(color: AppColors.gasBlue)),
              ),
            ],
          ),
        );
        return;
      }
      if (!status.isGranted) {
        // 권한 요청 → 네이티브 다이얼로그 바로 표시
        final result = await Permission.notification.request();
        if (!result.isGranted) return; // 거부하면 토글 변경 안 함
      }
    }
    setState(() => _toggling = true);
    await AlertService().setAlertsEnabled(value);
    setState(() {
      _enabled = value;
      _toggling = false;
    });
  }

  Future<void> _unsubscribe(String id) async {
    await AlertService().unsubscribe(id);
    setState(() => _ids.remove(id));
    // 더 이상 구독 없으면 접기
    if (_ids.isEmpty) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        // ── 헤더 행 ──
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(
            _enabled ? Icons.notifications_rounded : Icons.notifications_off_rounded,
            size: 22,
            color: _enabled ? AppColors.gasBlue : secondaryColor,
          ),
          title: Text('가격 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _enabled
                ? '${_ids.isEmpty ? '알림 주유소 없음' : '${_ids.length}곳 설정됨'} · 매일 $_alertTimeText 발송'
                : '알림 꺼짐',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 알림 시각 설정 버튼 (켜진 상태일 때만)
              if (_enabled)
                GestureDetector(
                  onTap: _pickAlertTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gasBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _alertTimeText,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gasBlue),
                    ),
                  ),
                ),
              // 드롭다운 화살표 (구독 있을 때만)
              if (_ids.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: mutedColor),
                    ),
                  ),
                ),
              // 전체 on/off 스위치
              _toggling
                  ? const SizedBox(
                      width: 36, height: 20,
                      child: Center(child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))))
                  : Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _enabled,
                        onChanged: _toggleEnabled,
                        activeColor: AppColors.gasBlue,
                      ),
                    ),
            ],
          ),
          onTap: _ids.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
        ),

        // ── 드롭다운: 구독 주유소 리스트 ──
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: _ids.map((id) {
                      final name = AlertService().stationName(id);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        leading: Icon(Icons.local_gas_station_rounded,
                            size: 18, color: AppColors.gasBlue),
                        title: Text(name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 20),
                          onPressed: () => _unsubscribe(id),
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

