import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/api_service.dart';

/// 충전 사업자 선택 바텀시트 (공용) — AI 추천 필터와 지도·홈 EV 필터가 함께 사용.
///
/// [initial] : 현재 부분선택된 canonical 사업자명(빈 집합 = 전체).
/// [extraReps] : /operators 목록에 없지만 대표 칩으로 넣고 싶은 항목
///   (예: 지도 필터의 Tesla). {'name': 'Tesla', 'count': 0} 형태.
/// 반환: 새 선택 canonical 이름 집합(빈 집합 = 전체 선택). 취소 시 null.
Future<Set<String>?> showEvOperatorPicker(
  BuildContext context, {
  required Set<String> initial,
  List<Map<String, dynamic>> extraReps = const [],
  Color accent = const Color(0xFF10B981),
}) async {
  // 목록 로드(세션 캐시). 실패해도 전체=빈 상태로 열림.
  await _EvOperatorCatalog.ensureLoaded();
  if (!context.mounted) return null;

  final rep = [...extraReps, ..._EvOperatorCatalog.representatives];
  final all = _EvOperatorCatalog.all;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // '전체' 디폴트를 '모두 켜짐(초록)'으로 표현하기 위한 전체 이름 집합.
  final allNames = <String>{
    ...all.map((o) => (o['name'] as String? ?? '')),
    ...rep.map((o) => (o['name'] as String? ?? '')),
  }..removeWhere((n) => n.isEmpty);
  final total = allNames.length;
  // 저장된 필터 없음(빈 집합) = 전체 → 모두 켜서 시작. 부분선택이면 그것만.
  final sel = initial.isEmpty ? Set<String>.from(allNames) : Set<String>.from(initial);
  String query = '';
  final searchCtrl = TextEditingController();

  final result = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final q = query.trim();
        final isAll = total == 0 || sel.length >= total;
        final searchHits = q.isEmpty
            ? const <Map<String, dynamic>>[]
            : all
                .where((o) => (o['name'] as String? ?? '').contains(q))
                .take(30)
                .toList();

        Widget chip(String name, int count, {bool fromSearch = false}) {
          final on = sel.contains(name);
          return GestureDetector(
            onTap: () => setSheet(() {
              if (on) {
                sel.remove(name);
              } else {
                sel.add(name);
              }
              // 검색으로 고르면 검색을 비우고 선택 목록으로 복귀 → 이어서 또 검색·추가 가능.
              if (fromSearch) {
                searchCtrl.clear();
                query = '';
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: on
                    ? accent.withValues(alpha: 0.12)
                    : (isDark ? AppColors.darkBg : const Color(0xFFF4F5F7)),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: on ? accent : Colors.transparent, width: 1.3),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (on)
                  Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.check, size: 14, color: accent)),
                Text(name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on
                            ? accent
                            : (isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF374151)))),
              ]),
            ),
          );
        }

        // 한글 초성 그룹(가나다순). 쌍자음은 기본자음으로, 영문/기타는 별도.
        String initialOf(String name) {
          if (name.isEmpty) return '#';
          final c = name.codeUnitAt(0);
          if (c >= 0xAC00 && c <= 0xD7A3) {
            const leads = ['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
            const merge = {'ㄲ':'ㄱ','ㄸ':'ㄷ','ㅃ':'ㅂ','ㅆ':'ㅅ','ㅉ':'ㅈ'};
            final l = leads[(c - 0xAC00) ~/ 588];
            return merge[l] ?? l;
          }
          if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) return 'A-Z';
          return '#';
        }

        const initialOrder = ['ㄱ','ㄴ','ㄷ','ㄹ','ㅁ','ㅂ','ㅅ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ','A-Z','#'];
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final o in all) {
          (grouped[initialOf((o['name'] as String? ?? ''))] ??= []).add(o);
        }
        for (final list in grouped.values) {
          list.sort((a, b) =>
              (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
        }

        final muted =
            isDark ? AppColors.darkTextMuted : const Color(0xFF9CA3AF);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface1 : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCardBorder
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Text('충전 사업자 선택',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : const Color(0xFF111827))),
                const SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.only(
                      left: isAll ? 7 : 8, right: 8, top: 3, bottom: 3),
                  decoration: BoxDecoration(
                    color: isAll ? accent : accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isAll) ...[
                      const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                      const SizedBox(width: 2),
                    ],
                    Text(isAll ? '전체' : '${sel.length}개 선택',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isAll ? Colors.white : accent)),
                  ]),
                ),
                const Spacer(),
                if (!isAll)
                  GestureDetector(
                    onTap: () => setSheet(() => sel..clear()..addAll(allNames)),
                    child: Text('전체로',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : const Color(0xFF6B7280))),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('켜진 사업자 충전소만 보여줘요. 전체면 모든 사업자.',
                  style: TextStyle(fontSize: 12.5, color: muted)),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                onChanged: (v) => setSheet(() => query = v),
                decoration: InputDecoration(
                  hintText: '사업자 검색 (예: 환경부, 스타코프)',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? AppColors.darkBg : const Color(0xFFF4F5F7),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.isEmpty) ...[
                        Text('자주 쓰는 사업자',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: muted)),
                        const SizedBox(height: 10),
                        Wrap(
                            children: rep
                                .map((o) => chip(o['name'] as String? ?? '',
                                    (o['count'] as num?)?.toInt() ?? 0))
                                .toList()),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('전체 충전소 사업자',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: muted)),
                            GestureDetector(
                              onTap: () => setSheet(() => isAll
                                  ? sel.clear()
                                  : (sel..clear()..addAll(allNames))),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child:
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(
                                      isAll
                                          ? Icons.clear_rounded
                                          : Icons.check_rounded,
                                      size: 14,
                                      color: accent),
                                  const SizedBox(width: 3),
                                  Text(isAll ? '전체 해제' : '전체 선택',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: accent)),
                                ]),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final ini in initialOrder)
                          if ((grouped[ini] ?? const []).isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(ini,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isDark
                                          ? AppColors.darkTextMuted
                                          : const Color(0xFFB0B6C0))),
                            ),
                            Wrap(
                                children: grouped[ini]!
                                    .map((o) => chip(o['name'] as String? ?? '',
                                        (o['count'] as num?)?.toInt() ?? 0))
                                    .toList()),
                            const SizedBox(height: 10),
                          ],
                      ] else if (searchHits.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('검색 결과가 없어요',
                              style: TextStyle(fontSize: 13, color: muted)),
                        )
                      else
                        Wrap(
                            children: searchHits
                                .map((o) => chip(o['name'] as String? ?? '',
                                    (o['count'] as num?)?.toInt() ?? 0,
                                    fromSearch: true))
                                .toList()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // 전체(모두 켬)거나 아무것도 안 켠 경우 = 필터 없음(전체) → 빈 집합.
                    // 부분선택일 때만 그 목록 반환.
                    final result = (isAll || sel.isEmpty)
                        ? <String>{}
                        : Set<String>.from(sel);
                    Navigator.pop(ctx, result);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                      (isAll || sel.isEmpty)
                          ? '전체로 보기'
                          : '${sel.length}개 사업자 적용',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  searchCtrl.dispose();
  return result;
}

/// /operators 목록 세션 캐시 — 시트 열 때마다 재요청하지 않도록.
class _EvOperatorCatalog {
  static List<Map<String, dynamic>> representatives = [];
  static List<Map<String, dynamic>> all = [];
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded && all.isNotEmpty) return;
    try {
      final d = await ApiService().getEvOperators();
      List<Map<String, dynamic>> conv(dynamic v) => (v as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      representatives = conv(d['representatives']);
      all = conv(d['all']);
      _loaded = true;
    } catch (_) {
      // 실패 시 빈 목록 → 전체(빈 상태)로 열림.
    }
  }
}
