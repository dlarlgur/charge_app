import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../../data/services/alert_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  VehicleType _vehicleType = VehicleType.gas;
  FuelType _fuelType = FuelType.gasoline;
  List<String> _chargerTypes = ['02', '04'];
  int _radius = 5000;

  // 차종에 따라 스텝 수가 달라짐 (마지막은 항상 알림 권한)
  // gas:  0(차종) → 1(유종) → 2(알림)              = 3스텝
  // ev:   0(차종) → 1(충전기) → 2(알림)            = 3스텝
  // both: 0(차종) → 1(유종) → 2(충전기) → 3(알림) = 4스텝
  int get _totalSteps => _vehicleType == VehicleType.both ? 4 : 3;

  bool get _isBoth => _vehicleType == VehicleType.both;
  bool get _isEv => _vehicleType == VehicleType.ev;

  // 현재 스텝이 어떤 내용인지
  _StepKind get _currentKind {
    switch (_vehicleType) {
      case VehicleType.gas:
        return [_StepKind.vehicle, _StepKind.fuel, _StepKind.notification][_step];
      case VehicleType.ev:
        return [_StepKind.vehicle, _StepKind.charger, _StepKind.notification][_step];
      case VehicleType.both:
        return [_StepKind.vehicle, _StepKind.fuel, _StepKind.charger, _StepKind.notification][_step];
    }
  }

  Color get _accentColor {
    if (_currentKind == _StepKind.charger) return AppColors.evGreen;
    return AppColors.gasBlue;
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() async {
    // 알림 권한 요청
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    AlertService().init();

    final notifier = ref.read(settingsProvider.notifier);
    notifier.setVehicleType(_vehicleType);
    notifier.setFuelType(_fuelType);
    notifier.setChargerTypes(_chargerTypes);
    notifier.setRadius(_radius);
    notifier.completeOnboarding();

    // 온보딩에서 선택한 커넥터 타입을 EV 필터에도 반영
    if (_vehicleType == VehicleType.ev || _vehicleType == VehicleType.both) {
      ref.read(evFilterProvider.notifier).update(
        ref.read(evFilterProvider).copyWith(chargerTypes: List<String>.from(_chargerTypes)),
      );
    }
    // 온보딩에서 선택한 유종을 Gas 필터에도 반영
    if (_vehicleType == VehicleType.gas || _vehicleType == VehicleType.both) {
      ref.read(gasFilterProvider.notifier).update(
        ref.read(gasFilterProvider).copyWith(fuelTypes: [_fuelType.code]),
      );
    }

    context.go('/home');
  }

  String get _stepTitle {
    switch (_currentKind) {
      case _StepKind.vehicle: return '어떤 차를\n운전하시나요?';
      case _StepKind.fuel:    return '주로 넣는 기름은\n무엇인가요?';
      case _StepKind.charger: return '충전기 타입을\n선택해주세요';
      case _StepKind.notification: return '가격 알림을\n받아보세요';
    }
  }

  String get _stepSubtitle {
    switch (_currentKind) {
      case _StepKind.vehicle: return '선택에 맞춰 맞춤 화면을 보여드려요';
      case _StepKind.fuel:    return '설정에서 변경할 수 있어요';
      case _StepKind.charger: return '복수 선택 가능 · 설정에서 변경 가능';
      case _StepKind.notification: return '즐겨찾는 주유소 가격이 내리면 알려드려요';
    }
  }

  String get _stepLabel {
    final kindLabel = switch (_currentKind) {
      _StepKind.fuel         => ' · 내연기관',
      _StepKind.charger      => ' · 전기차',
      _StepKind.notification => ' · 알림',
      _                      => '',
    };
    return '${_step + 1} / $_totalSteps$kindLabel';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _step == _totalSteps - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // 프로그레스 바
              Row(
                children: List.generate(_totalSteps, (i) => Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? _accentColor
                          : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 24),
              Text(
                _stepLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: _accentColor),
              ),
              const SizedBox(height: 8),
              Text(_stepTitle, style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.4)),
              const SizedBox(height: 4),
              Text(_stepSubtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              Expanded(child: SingleChildScrollView(child: _buildStepContent())),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLast ? AppColors.gasBlueDark : _accentColor,
                  ),
                  child: Text(isLast ? '알림 허용하고 시작하기' : '다음'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentKind) {
      case _StepKind.vehicle:      return _vehicleStep();
      case _StepKind.fuel:         return _fuelStep();
      case _StepKind.charger:      return _chargerStep();
      case _StepKind.notification: return _notificationStep();
    }
  }

  // ─── Step: 차종 선택 ───
  Widget _vehicleStep() {
    return Column(
      children: VehicleType.values.map((type) {
        final isSelected = _vehicleType == type;
        final emoji = type == VehicleType.gas ? '⛽' : type == VehicleType.ev ? '🔋' : '⚡';
        final desc = type == VehicleType.gas ? '휘발유 · 경유 · LPG'
            : type == VehicleType.ev ? 'DC콤보 · AC완속 · 급속' : 'PHEV 또는 차량 2대 이상';

        return _optionCard(
          isSelected: isSelected,
          onTap: () => setState(() {
            _vehicleType = type;
            // 차종 바꾸면 step이 0으로 돌아가도록 (다음 스텝 수가 달라지므로)
            _step = 0;
          }),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(desc, style: Theme.of(context).textTheme.labelSmall),
                ],
              )),
              _radioCircle(isSelected),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Step: 유종 선택 ───
  Widget _fuelStep() {
    return Column(
      children: FuelType.values.map((type) => _optionCard(
        isSelected: _fuelType == type,
        onTap: () => setState(() => _fuelType = type),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(type.label, style: Theme.of(context).textTheme.titleMedium),
            _radioCircle(_fuelType == type),
          ],
        ),
      )).toList(),
    );
  }

  // ─── Step: 충전기 타입 (복수 선택) ───
  Widget _chargerStep() {
    // 실제 사용: 01=DC차데모, 02=AC완속, 03=DC차데모+AC3상, 04=DC콤보, 07=AC3상, 09=NACS, SC=슈퍼차저
    final types = [
      ('02', 'AC완속'),
      ('07', 'AC3상'),
      ('04', 'DC콤보'),
      ('01', 'DC차데모'),
      ('09', 'NACS'),
      ('SC', '슈퍼차저'),
    ];

    return Column(
      children: types.map((t) {
        final isSelected = _chargerTypes.contains(t.$1);
        return _optionCard(
          isSelected: isSelected,
          accentColor: AppColors.evGreen,
          onTap: () => setState(() {
            if (isSelected) {
              _chargerTypes.remove(t.$1);
            } else {
              _chargerTypes.add(t.$1);
            }
          }),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.$2, style: Theme.of(context).textTheme.titleMedium),
              _checkCircle(isSelected),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── 공통 옵션 카드 ───
  Widget _optionCard({
    required bool isSelected,
    required VoidCallback onTap,
    required Widget child,
    Color? accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = accentColor ?? AppColors.gasBlue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDark ? 0.08 : 0.06)
              : (isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.4)
                : (isDark ? const Color(0x0FFFFFFF) : const Color(0xFFE2E8F0)),
            width: 0.5,
          ),
        ),
        child: child,
      ),
    );
  }

  // 단일 선택 원형 라디오
  Widget _radioCircle(bool isSelected) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.gasBlue : AppColors.darkTextMuted,
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(child: Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.gasBlue),
            ))
          : null,
    );
  }

  // ─── Step: 알림 권한 ───
  Widget _notificationStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      ('⛽', '주유 가격 인하 알림', '즐겨찾기 주유소 가격이 내리면 알려드려요'),
      ('🔕', '광고 없음', '불필요한 마케팅 알림은 보내지 않아요'),
      ('⚙️', '언제든 해제 가능', '설정에서 알림을 켜고 끌 수 있어요'),
    ];
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.gasBlue.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_rounded, size: 40, color: AppColors.gasBlue),
        ),
        const SizedBox(height: 28),
        ...items.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.darkCardBorder : const Color(0xFFDDE3EC), width: 1),
          ),
          child: Row(
            children: [
              Text(item.$1, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(item.$3, style: TextStyle(fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                ],
              )),
            ],
          ),
        )),
      ],
    );
  }

  // 복수 선택 체크박스 스타일
  Widget _checkCircle(bool isSelected) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.evGreen : Colors.transparent,
        border: Border.all(
          color: isSelected ? AppColors.evGreen : AppColors.darkTextMuted,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}

enum _StepKind { vehicle, fuel, charger, notification }
