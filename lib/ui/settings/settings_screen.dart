import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/alert_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../widgets/shared_widgets.dart';

const _chargerTypeOptions = <({String code, String label})>[
  (code: '02', label: 'AC완속'),
  (code: '07', label: 'AC3상'),
  (code: '04', label: 'DC콤보'),
  (code: '01', label: 'DC차데모'),
  (code: '09', label: 'NACS'),
  (code: 'SC', label: '슈퍼차저'),
  (code: 'DT', label: '데스티네이션'),
];

String _chargerLabel(String code) =>
    _chargerTypeOptions.firstWhere((t) => t.code == code, orElse: () => (code: code, label: code)).label;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[SettingsScreen] build 진입');
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
        children: [
          _SectionCard(
            isDark: isDark,
            icon: Icons.directions_car_rounded,
            accent: AppColors.gasBlue,
            title: '차량 설정',
            summary: _vehicleSummary(settings),
            children: [
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
            ],
          ),
          ValueListenableBuilder<int>(
            valueListenable: AlertService().subsChanged,
            builder: (_, __, ___) => _SectionCard(
              isDark: isDark,
              icon: Icons.notifications_active_rounded,
              accent: AppColors.warning,
              title: '알림',
              summary: _alertSummary(),
              children: [
                _AlertSettingTile(isDark: isDark),
                _EvAlarmSettingTile(isDark: isDark),
              ],
            ),
          ),
          _SectionCard(
            isDark: isDark,
            icon: Icons.palette_rounded,
            accent: AppColors.evGreen,
            title: '앱 설정',
            summary: themeMode == ThemeMode.dark ? '다크 모드' : '라이트 모드',
            children: [
              _settingTile(context, isDark,
                icon: Icons.dark_mode_rounded,
                title: '테마',
                value: themeMode == ThemeMode.dark ? '다크' : '라이트',
                onTap: () => _showThemePicker(context, ref),
              ),
            ],
          ),
          _SupportSection(isDark: isDark),
          _SectionCard(
            isDark: isDark,
            icon: Icons.info_outline_rounded,
            accent: AppColors.gasBlue,
            title: '정보',
            summary: 'v${DkswCore.appVersion}',
            children: [
              _settingTile(context, isDark,
                icon: Icons.verified_outlined,
                title: '앱 버전',
                value: DkswCore.appVersion,
              ),
              _settingTile(context, isDark,
                icon: Icons.description_outlined,
                title: '정책 및 약관',
                onTap: () => context.push('/policies'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Text(
              '유가 정보 출처: 한국석유공사 오피넷(www.opinet.co.kr)\n충전소 정보 출처: 환경부 전기차 충전소 공공데이터',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _vehicleSummary(SettingsState s) {
    final parts = <String>[s.vehicleType.label];
    if (s.vehicleType != VehicleType.ev) parts.add(s.fuelType.label);
    if (s.vehicleType != VehicleType.gas) {
      if (s.chargerTypes.isEmpty) {
        parts.add('충전기 미선택');
      } else if (s.chargerTypes.length == 1) {
        parts.add(_chargerLabel(s.chargerTypes.first));
      } else {
        parts.add('${_chargerLabel(s.chargerTypes.first)} 외 ${s.chargerTypes.length - 1}');
      }
    }
    parts.add('${(s.radius / 1000).toInt()}Km');
    return parts.join(' · ');
  }

  String _alertSummary() {
    final gasCount = AlertService().subscribedStationIds.length;
    final evCount = AlertService().evAlarmStationIds.length;
    final enabled = AlertService().alertsEnabled;
    if (!enabled && gasCount == 0 && evCount == 0) return '알림 꺼짐';
    final parts = <String>[];
    if (gasCount > 0) parts.add('주유소 $gasCount곳');
    if (evCount > 0) parts.add('충전소 $evCount곳');
    if (parts.isEmpty) return enabled ? '알림 켜짐' : '알림 꺼짐';
    return parts.join(' · ');
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
              ..._chargerTypeOptions.map((t) {
                final isSelected = selected.contains(t.code);
                return ListTile(
                  title: Text(t.label),
                  trailing: isSelected
                      ? const Icon(Icons.check_box_rounded, color: AppColors.evGreen)
                      : const Icon(Icons.check_box_outline_blank_rounded),
                  onTap: () {
                    setState(() {
                      if (isSelected) selected.remove(t.code);
                      else selected.add(t.code);
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

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color accent;
  final String title;
  final String summary;
  final List<Widget> children;

  const _SectionCard({
    required this.isDark,
    required this.icon,
    required this.accent,
    required this.title,
    required this.summary,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF141823) : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            letterSpacing: -0.2,
                          )),
                      const SizedBox(height: 2),
                      Text(summary,
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryColor,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: mutedColor.withOpacity(0.15)),
          const SizedBox(height: 4),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
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
        final result = await Permission.notification.request();
        if (!result.isGranted) return;
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
    if (_ids.isEmpty) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(
            _enabled ? Icons.notifications_rounded : Icons.notifications_off_rounded,
            size: 22,
            color: _enabled ? AppColors.gasBlue : secondaryColor,
          ),
          title: Text('주유 가격 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _enabled
                ? '${_ids.isEmpty ? '알림 주유소 없음' : '${_ids.length}곳 설정됨'} · 매일 $_alertTimeText 발송'
                : '알림 꺼짐',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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

class _EvAlarmSettingTile extends StatefulWidget {
  final bool isDark;
  const _EvAlarmSettingTile({required this.isDark});
  @override
  State<_EvAlarmSettingTile> createState() => _EvAlarmSettingTileState();
}

class _EvAlarmSettingTileState extends State<_EvAlarmSettingTile> {
  late List<String> _ids;
  late int _soundMode;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    AlertService().subsChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AlertService().subsChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _ids = AlertService().evAlarmStationIds;
      _soundMode = AlertService().evAlarmSoundMode;
      if (_ids.isEmpty) _expanded = false;
    });
  }

  Future<void> _unsubscribe(String id) async {
    await AlertService().unsubscribeEvAlarm(id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mutedColor = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(
            Icons.ev_station_rounded,
            size: 22,
            color: _ids.isEmpty ? secondaryColor : AppColors.evGreen,
          ),
          title: Text('충전소 현황 알림', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _ids.isEmpty ? '알림 설정된 충전소 없음' : '${_ids.length}/${AlertService.evAlarmMaxCount}곳 설정됨',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
          trailing: _ids.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: mutedColor),
                    ),
                  ),
                )
              : null,
          onTap: _ids.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
        ),
        if (_ids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text('알림 방식', style: TextStyle(fontSize: 12, color: mutedColor)),
                const SizedBox(width: 12),
                ...['소리', '진동', '무음'].asMap().entries.map((e) {
                  final idx = e.key;
                  final label = e.value;
                  final selected = _soundMode == idx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        AlertService().setEvAlarmSoundMode(idx);
                        setState(() => _soundMode = idx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.evGreen.withOpacity(0.15)
                              : (isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? AppColors.evGreen : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? AppColors.evGreen : secondaryColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
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
                      final name = AlertService().evAlarmStationName(id);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                        leading: const Icon(Icons.ev_station_rounded, size: 18, color: AppColors.evGreen),
                        title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
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

class _SupportSection extends StatefulWidget {
  final bool isDark;
  const _SupportSection({required this.isDark});

  @override
  State<_SupportSection> createState() => _SupportSectionState();
}

class _SupportCounts {
  final int notices;
  final int events;
  final int faqs;
  const _SupportCounts(this.notices, this.events, this.faqs);
}

class _SupportSectionState extends State<_SupportSection> {
  late Future<_SupportCounts> _future;

  @override
  void initState() {
    super.initState();
    debugPrint('[SupportSection] initState → _load() 호출');
    _future = _load();
  }

  Future<_SupportCounts> _load() async {
    debugPrint('[SupportSection] _load 시작');
    final results = await Future.wait([
      DkswCore.fetchNotices(),
      DkswCore.fetchEvents(),
      DkswCore.fetchFaqs(),
    ]);
    final c = _SupportCounts(
      (results[0] as List).length,
      (results[1] as List).length,
      (results[2] as List).length,
    );
    debugPrint('[SupportSection] _load 완료: notices=${c.notices} events=${c.events} faqs=${c.faqs}');
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final boot = DkswCore.lastBootstrap?.counts;
    debugPrint('[SupportSection] build — lastBootstrap.counts = ${boot == null ? "null" : "n=${boot.notices} e=${boot.events} f=${boot.faqs}"}');
    final seed = boot == null
        ? null
        : _SupportCounts(boot.notices, boot.events, boot.faqs);

    return FutureBuilder<_SupportCounts>(
      future: _future,
      initialData: seed,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) return const SizedBox.shrink();
        final hasNotices = c.notices > 0;
        final hasEvents = c.events > 0;
        final hasFaqs = c.faqs > 0;
        if (!hasNotices && !hasEvents && !hasFaqs) return const SizedBox.shrink();

        final parts = <String>[];
        if (hasNotices) parts.add('공지 ${c.notices}');
        if (hasEvents) parts.add('이벤트 ${c.events}');
        if (hasFaqs) parts.add('FAQ ${c.faqs}');

        return _SectionCard(
          isDark: widget.isDark,
          icon: Icons.support_agent_rounded,
          accent: AppColors.warning,
          title: '고객 지원',
          summary: parts.join(' · '),
          children: [
            if (hasNotices)
              _supportTile(context,
                  icon: Icons.campaign_rounded,
                  title: '공지사항',
                  count: c.notices,
                  onTap: () => context.push('/notices')),
            if (hasEvents)
              _supportTile(context,
                  icon: Icons.celebration_rounded,
                  title: '이벤트',
                  count: c.events,
                  onTap: () => context.push('/events')),
            if (hasFaqs)
              _supportTile(context,
                  icon: Icons.help_outline_rounded,
                  title: '자주 묻는 질문',
                  count: c.faqs,
                  onTap: () => context.push('/faq')),
          ],
        );
      },
    );
  }

  Widget _supportTile(BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
  }) {
    final isDark = widget.isDark;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 22, color: secondary),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$count', style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 20, color: muted),
      ]),
      onTap: onTap,
    );
  }
}
