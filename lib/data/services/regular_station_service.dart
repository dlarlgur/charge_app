import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import 'user_sync_service.dart';

/// 단골주유소 한 곳 (주유 전용, 충전소 X).
/// 서버에는 id 만 CSV 로 저장하고(prefs.regularStationId) 이름·브랜드는 로컬 표시용.
class RegularStation {
  final String id;
  final String name;
  final String brand;
  const RegularStation(
      {required this.id, required this.name, required this.brand});
}

/// 단골주유소 저장/동기화 + '경유 길안내' 기반 등록 유도.
///
/// - **최대 3곳** (집 앞·회사 앞 등 — 설계서 §1, 2026-08-18 확장).
/// - 저장: Hive `settings` 박스 키 1개에 리스트. 구버전 단수 저장분(Map)은
///   읽을 때 1개짜리 리스트로 승격 (형 기기 기존 값 대비).
/// - 로그인 미러: 변경 시 putPrefs(regularStationId) — **CSV** "A123,B456".
///   비로그인은 내부에서 조용히 skip, 요청에는 로컬 값을 실어 보내므로 완전 동작.
/// - 비교 표시는 서버가 후보군에 걸린 단골 중 최저 score 1곳만 내려주므로
///   (`regular_compare.station_id`) 앱은 그 1곳만 그린다 — 여러 단골 나열 금지.
/// - 유도: AI 추천 결과에서 경유 길안내를 실행한 주유소를 station_id 별로 카운트,
///   같은 곳 3회째에 1회만 등록 제안 바텀시트. 거절하면 다시 묻지 않고,
///   3곳이 차 있으면 띄우지 않는다 (설계서 §6).
class RegularStationService {
  RegularStationService._();

  static const maxCount = 3;
  static const _kStationKey = 'regular_gas_station'; // [{id,name,brand}] 최대 3
  static const _kNavCountsKey = 'regular_gas_nav_counts'; // {stationId: count}
  static const _kPromptDoneKey = 'regular_gas_prompt_done'; // 유도 1회 소진 플래그
  static const promptThreshold = 3;

  /// 즐겨찾기와 혼동 방지 카피 — 등록 다이얼로그·유도 시트·설정 전부에 노출 (형 요구).
  static const copyLine = '즐겨찾기와 달라요 — AI 추천에서 단골 대비 얼마나 이득인지 비교해 드려요';

  /// 설정 타일·상세화면 버튼이 구독한다.
  static final ValueNotifier<List<RegularStation>> notifier =
      ValueNotifier(_read());

  static List<RegularStation> get all => notifier.value;

  static bool get isFull => all.length >= maxCount;

  static bool contains(String id) => all.any((r) => r.id == id);

  static RegularStation? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 서버 동기화·분석 요청용 CSV ("A123,B456"). 등록 없으면 null.
  static String? get csv =>
      all.isEmpty ? null : all.map((r) => r.id).join(',');

  static RegularStation? _fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return RegularStation(
      id: id,
      name: (raw['name'] ?? '').toString(),
      brand: (raw['brand'] ?? '').toString(),
    );
  }

  static List<RegularStation> _read() {
    try {
      final raw = Hive.box(AppConstants.settingsBox).get(_kStationKey);
      // 구버전 단수 저장분 승격 (Map 1개 → 리스트 1개)
      final single = _fromMap(raw);
      if (single != null) return [single];
      if (raw is List) {
        final out = <RegularStation>[];
        for (final e in raw) {
          final r = _fromMap(e);
          if (r != null && !out.any((o) => o.id == r.id)) out.add(r);
          if (out.length >= maxCount) break;
        }
        return out;
      }
    } catch (_) {}
    return const [];
  }

  static void _writeLocal(List<RegularStation> list) {
    final capped = list.take(maxCount).toList();
    try {
      Hive.box(AppConstants.settingsBox).put(
          _kStationKey,
          capped
              .map((r) => {'id': r.id, 'name': r.name, 'brand': r.brand})
              .toList());
    } catch (_) {}
    notifier.value = capped;
  }

  static void _mirror() {
    UserSyncService.instance.putPrefs(regularStationId: csv ?? '');
  }

  /// 단골 추가 — 자리가 없으면 무시 (호출부가 교체 UI 로 유도할 책임).
  static void add({required String id, required String name, String brand = ''}) {
    if (id.isEmpty || contains(id) || isFull) return;
    _writeLocal([...all, RegularStation(id: id, name: name, brand: brand)]);
    _mirror();
  }

  /// 기존 단골 [oldId] 자리를 새 주유소로 교체 (3곳 찼을 때의 등록 경로).
  static void replace(String oldId,
      {required String id, required String name, String brand = ''}) {
    if (id.isEmpty || contains(id)) return;
    final next = all
        .map((r) => r.id == oldId
            ? RegularStation(id: id, name: name, brand: brand)
            : r)
        .toList();
    _writeLocal(next);
    _mirror();
  }

  /// 단골 1곳 해제.
  static void remove(String id) {
    if (!contains(id)) return;
    _writeLocal(all.where((r) => r.id != id).toList());
    _mirror();
  }

  /// 로그인 동기화(_applyRemote) 전용 — 서버 prefs.regularStationId(CSV) 반영.
  /// null(구서버/필드 없음)=아무것도 안 함, ''=전체 해제, CSV=그 목록으로.
  /// 로컬에 있는 id 는 메타(이름·브랜드)를 유지하고, 다른 기기에서 등록한 id 는
  /// 메타 없이 들어와 UI 가 폴백한다. 서버 미러는 하지 않는다(루프 방지).
  static void applyRemote(dynamic v) {
    if (v == null || v is! String) return;
    final ids = v
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(maxCount)
        .toList();
    if (ids.isEmpty) {
      if (all.isNotEmpty) _writeLocal(const []);
      return;
    }
    final next = [
      for (final id in ids)
        byId(id) ?? RegularStation(id: id, name: '', brand: ''),
    ];
    if (next.length == all.length && ids.every(contains)) return; // 변화 없음
    _writeLocal(next);
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
    if (isFull || contains(id)) return; // 자리 없음·이미 단골 — 유도 불필요
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
    if (ok == true) add(id: id, name: name, brand: brand ?? '');
  }
}

/// 3곳 만석 시 교체 대상 선택 시트 — "어느 것을 바꿀까요?" (무조건 덮어쓰기 금지).
/// 선택한 단골을 돌려주고, 닫으면 null. 상세화면·즐겨찾기 화면 공용.
Future<RegularStation?> showRegularReplacePicker(BuildContext context,
    {required String newName}) {
  return showModalBottomSheet<RegularStation>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
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
                Text('어느 단골을 바꿀까요?',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: textPrimary)),
                const SizedBox(height: 6),
                Text('단골주유소는 최대 3곳이에요.\n$newName(으)로 바꿀 자리를 골라주세요.',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, height: 1.5, color: muted)),
                const SizedBox(height: 10),
                for (final r in RegularStationService.all)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.loyalty_rounded,
                        size: 20, color: AppColors.gasBlue),
                    title: Text(r.name.trim().isEmpty ? '단골주유소' : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 20, color: muted),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('취소',
                      style: TextStyle(fontSize: 13.5, color: muted)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
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
              Text(
                  '최근 세 번이나 들렀어요.\n${RegularStationService.copyLine}.',
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
