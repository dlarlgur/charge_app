import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import 'user_sync_service.dart';

/// 단골주유소 한 곳 — 계정당 수동 등록 1곳 (주유 전용, 충전소 X).
/// 서버에는 id 만 저장하고(prefs.regularStationId) 이름·브랜드는 로컬 표시용.
class RegularStation {
  final String id;
  final String name;
  final String brand;
  const RegularStation(
      {required this.id, required this.name, required this.brand});
}

/// 단골주유소 저장/동기화 + '경유 길안내' 기반 등록 유도.
///
/// - 저장: Hive `settings` 박스 키 1개 (`ai_gas_pref_brands` 와 동일 배관 패턴).
/// - 로그인 미러: set/clear 시 UserSyncService.putPrefs(regularStationId) —
///   비로그인은 내부에서 조용히 skip, 요청에는 로컬 값을 실어 보내므로 완전 동작.
/// - 유도: AI 추천 결과에서 경유 길안내를 실행한 주유소를 station_id 별로 카운트,
///   같은 곳 3회째에 1회만 등록 제안 바텀시트. 거절하면 다시 묻지 않는다
///   (등록 전까지 유도는 총 1회 — 사용 방해 금지, 설계서 §6).
class RegularStationService {
  RegularStationService._();

  static const _kStationKey = 'regular_gas_station'; // {id, name, brand}
  static const _kNavCountsKey = 'regular_gas_nav_counts'; // {stationId: count}
  static const _kPromptDoneKey = 'regular_gas_prompt_done'; // 유도 1회 소진 플래그
  static const promptThreshold = 3;

  /// 설정 타일·상세화면 버튼이 구독한다.
  static final ValueNotifier<RegularStation?> notifier = ValueNotifier(_read());

  static RegularStation? get current => notifier.value;

  static RegularStation? _read() {
    try {
      final raw = Hive.box(AppConstants.settingsBox).get(_kStationKey);
      if (raw is Map) {
        final id = (raw['id'] ?? '').toString();
        if (id.isEmpty) return null;
        return RegularStation(
          id: id,
          name: (raw['name'] ?? '').toString(),
          brand: (raw['brand'] ?? '').toString(),
        );
      }
    } catch (_) {}
    return null;
  }

  static void _writeLocal(String id, String name, String brand) {
    try {
      Hive.box(AppConstants.settingsBox)
          .put(_kStationKey, {'id': id, 'name': name, 'brand': brand});
    } catch (_) {}
    notifier.value = RegularStation(id: id, name: name, brand: brand);
  }

  static void _clearLocal() {
    try {
      Hive.box(AppConstants.settingsBox).delete(_kStationKey);
    } catch (_) {}
    notifier.value = null;
  }

  /// 단골 등록/교체 — 로컬 저장 + 서버 미러(회원만, 내부 skip).
  static void set({required String id, required String name, String brand = ''}) {
    if (id.isEmpty) return;
    _writeLocal(id, name, brand);
    UserSyncService.instance.putPrefs(regularStationId: id);
  }

  /// 단골 해제 — 서버에는 빈 문자열로 미러해 계정에서도 지운다.
  static void clear() {
    _clearLocal();
    UserSyncService.instance.putPrefs(regularStationId: '');
  }

  /// 로그인 동기화(_applyRemote) 전용 — 서버 prefs.regularStationId 반영.
  /// null(구서버/필드 없음)=아무것도 안 함, ''=해제, id=등록.
  /// 다른 기기에서 등록한 경우 표시 메타(이름)가 없어 빈 값으로 두고 UI 가 폴백한다.
  static void applyRemote(dynamic v) {
    if (v == null || v is! String) return;
    if (v.isEmpty) {
      if (current != null) _clearLocal();
      return;
    }
    if (current?.id == v) return; // 같은 단골 — 로컬 메타(이름·브랜드) 유지
    _writeLocal(v, '', '');
  }

  /// AI 추천 결과 카드의 '경유 길안내' 실행 시 호출.
  /// 같은 주유소 [promptThreshold]회째에 1회만 등록 제안 바텀시트를 띄운다.
  static Future<void> onGasNavigated(
    BuildContext context, {
    required String id,
    required String name,
    String? brand,
  }) async {
    if (id.isEmpty) return;
    final Box box;
    try {
      box = Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return;
    }
    if (current != null) return; // 이미 단골 있음 — 유도 불필요
    if (box.get(_kPromptDoneKey, defaultValue: false) == true) return;

    final counts = <String, int>{};
    final raw = box.get(_kNavCountsKey);
    if (raw is Map) {
      raw.forEach((k, v) => counts['$k'] = (v is num) ? v.toInt() : 0);
    }
    final n = (counts[id] ?? 0) + 1;
    counts[id] = n;
    try {
      box.put(_kNavCountsKey, counts);
    } catch (_) {}
    if (n != promptThreshold) return; // 정확히 3회째에 1회만
    if (!context.mounted) return;

    // 시트를 띄우는 순간 유도 소진 — 거절이든 바깥 탭이든 다시 묻지 않는다.
    try {
      box.put(_kPromptDoneKey, true);
    } catch (_) {}
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RegularPromptSheet(name: name),
    );
    if (ok == true) set(id: id, name: name, brand: brand ?? '');
  }
}

/// 등록 제안 바텀시트 — 기존 내비 시트 톤(흰 카드 + 라운드 22 + gasBlue CTA) 재사용.
class _RegularPromptSheet extends StatelessWidget {
  final String name;
  const _RegularPromptSheet({required this.name});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface1 : Colors.white;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x33FFFFFF)
                      : const Color(0xFFDDE3EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.gasBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.loyalty_rounded,
                    size: 27, color: AppColors.gasBlue),
              ),
              const SizedBox(height: 14),
              Text('여기를 단골로 등록할까요?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: textPrimary)),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary)),
              const SizedBox(height: 4),
              Text('최근 세 번이나 들렀어요. 단골로 등록하면\nAI 추천에서 단골과 비교해 드려요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: muted)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gasBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('단골로 등록',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('괜찮아요',
                    style: TextStyle(fontSize: 13.5, color: muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
