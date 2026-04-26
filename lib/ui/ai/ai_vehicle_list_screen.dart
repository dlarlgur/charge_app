import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import 'ai_vehicle_setup_screen.dart';

const _kPrimary = Color(0xFF1D9E75);
const _kPrimaryLight = Color(0xFFE1F5EE);
const _kEvBlue = Color(0xFF1D6FE0);
const _kEvBlueLight = Color(0xFFEAF1FD);

class AiVehicleListScreen extends StatefulWidget {
  /// true: 온보딩에서 진입 — 완료 시 루트까지 팝
  final bool isFromOnboarding;

  const AiVehicleListScreen({super.key, this.isFromOnboarding = false});

  @override
  State<AiVehicleListScreen> createState() => _AiVehicleListScreenState();
}

class _AiVehicleListScreenState extends State<AiVehicleListScreen> {
  List<VehicleProfile> _vehicles = [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final box = Hive.box(AppConstants.settingsBox);
    _vehicles = _parseVehicles(box);
    _selectedId = box.get(AppConstants.keyAiSelectedVehicleId) as String?;
    if (_selectedId == null && _vehicles.isNotEmpty) {
      _selectedId = _vehicles.first.id;
      box.put(AppConstants.keyAiSelectedVehicleId, _selectedId);
    }
  }

  List<VehicleProfile> _parseVehicles(Box box) {
    final raw = box.get(AppConstants.keyAiVehicles);
    if (raw == null) return [];
    try {
      final List decoded = jsonDecode(raw as String);
      return decoded
          .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _saveVehicles() {
    final box = Hive.box(AppConstants.settingsBox);
    box.put(
      AppConstants.keyAiVehicles,
      jsonEncode(_vehicles.map((v) => v.toJson()).toList()),
    );
  }

  void _selectVehicle(VehicleProfile v) {
    setState(() => _selectedId = v.id);
    final box = Hive.box(AppConstants.settingsBox);
    box.put(AppConstants.keyAiSelectedVehicleId, v.id);
    _syncToLegacyKeys(box, v);
  }

  void _syncToLegacyKeys(Box box, VehicleProfile v) {
    if (v.isGas) {
      box.put(AppConstants.keyAiFuelType, v.fuelType);
      box.put(AppConstants.keyAiTankCapacity, v.tankCapacity);
      box.put(AppConstants.keyAiEfficiency, v.efficiency);
      box.put(AppConstants.keyAiTargetMode, v.targetMode);
      box.put(AppConstants.keyAiTargetValue, v.targetValue);
      box.put(AppConstants.keyAiLiterTarget, v.targetValue);
    } else {
      box.put(AppConstants.keyAiTankCapacity, v.batteryCapacity);
      box.put(AppConstants.keyAiEfficiency, v.evEfficiency);
      box.put(AppConstants.keyAiTargetMode, 'FULL');
    }
    box.put(AppConstants.keyAiCurrentLevelPercent, v.currentLevelPercent);
  }

  void _deleteVehicle(VehicleProfile v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('차량 삭제'),
        content: Text('${v.name.isNotEmpty ? v.name : v.typeLabel}를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _vehicles.removeWhere((x) => x.id == v.id);
      if (_selectedId == v.id) {
        _selectedId = _vehicles.isNotEmpty ? _vehicles.first.id : null;
        if (_selectedId != null) {
          final box = Hive.box(AppConstants.settingsBox);
          box.put(AppConstants.keyAiSelectedVehicleId, _selectedId);
          _syncToLegacyKeys(box, _vehicles.first);
        }
      }
    });
    _saveVehicles();
  }

  void _goAddVehicle() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiVehicleSetupScreen()),
    );
    setState(_load);
  }

  void _goEditVehicle(VehicleProfile v) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiVehicleSetupScreen(editVehicleId: v.id),
      ),
    );
    setState(_load);
  }

  void _done() {
    if (widget.isFromOnboarding) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.isFromOnboarding
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Color(0xFF1a1a1a)),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text(
          '내 차량',
          style: TextStyle(
            color: Color(0xFF1a1a1a),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _done,
            child: Text(
              widget.isFromOnboarding ? '시작하기' : '완료',
              style: const TextStyle(
                color: _kPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _vehicles.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      itemCount: _vehicles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = _vehicles[i];
                        return _VehicleCard(
                          vehicle: v,
                          isSelected: v.id == _selectedId,
                          onTap: () => _selectVehicle(v),
                          onEdit: () => _goEditVehicle(v),
                          onDelete: () => _deleteVehicle(v),
                        );
                      },
                    ),
            ),

            // ── 차량 추가하기 버튼 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _goAddVehicle,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    '차량 추가하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPrimary,
                    side: const BorderSide(color: _kPrimary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.directions_car_rounded,
                size: 40, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 16),
          const Text(
            '등록된 차량이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '아래 버튼으로 차량을 추가해보세요',
            style: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
          ),
        ],
      ),
    );
  }
}

// ─── 차량 카드 ─────────────────────────────────────────────────────────────────
class _VehicleCard extends StatelessWidget {
  final VehicleProfile vehicle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _accent => vehicle.isEV ? _kEvBlue : _kPrimary;
  Color get _accentLight => vehicle.isEV ? _kEvBlueLight : _kPrimaryLight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _accentLight : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _accent : const Color(0xFFEEEEEE),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  const BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          children: [
            // 아이콘
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? _accent.withValues(alpha: 0.15)
                    : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                vehicle.isEV
                    ? Icons.bolt_rounded
                    : Icons.local_gas_station_rounded,
                size: 24,
                color: isSelected ? _accent : const Color(0xFFBBBBBB),
              ),
            ),
            const SizedBox(width: 14),

            // 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        vehicle.name.isNotEmpty ? vehicle.name : vehicle.typeLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? _accent : const Color(0xFF1a1a1a),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '선택됨',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildSubLabel(),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),

            // 수정 / 삭제
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBtn(
                  icon: Icons.edit_rounded,
                  onTap: onEdit,
                  color: const Color(0xFF888888),
                ),
                const SizedBox(width: 4),
                _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  onTap: onDelete,
                  color: const Color(0xFFDDAAAA),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubLabel() {
    if (vehicle.isEV) {
      return '배터리 ${vehicle.batteryCapacity.toStringAsFixed(0)}kWh  ·  전비 ${vehicle.evEfficiency.toStringAsFixed(1)}km/kWh';
    } else {
      final fuel = FuelType.fromCode(vehicle.fuelType).label;
      return '$fuel  ·  탱크 ${vehicle.tankCapacity.toStringAsFixed(0)}L  ·  연비 ${vehicle.efficiency.toStringAsFixed(1)}km/L';
    }
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _IconBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}
