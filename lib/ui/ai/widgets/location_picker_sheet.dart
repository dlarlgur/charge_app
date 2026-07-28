import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/place_service.dart';
import '../../favorites/place_picker_screen.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../data/services/api_service.dart';
import '../../../providers/providers.dart';
import '../ai_constants.dart';

/// 위치 선택 시트 — 출발지/목적지 검색 + 내위치/지도 옵션
class LocationPickerSheet extends ConsumerStatefulWidget {
  final bool isOrigin;
  final String? currentLocationAddress;
  final List<String> searchHistory;
  final List<Map<String, dynamic>> searchHistoryItems;
  final VoidCallback onMyLocation;
  final VoidCallback onMapPick;
  final Function(Map<String, dynamic>) onSearchResult;

  const LocationPickerSheet({
    super.key,
    required this.isOrigin,
    required this.currentLocationAddress,
    required this.searchHistory,
    required this.searchHistoryItems,
    required this.onMyLocation,
    required this.onMapPick,
    required this.onSearchResult,
  });

  @override
  ConsumerState<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<LocationPickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _myLocationSelected = false; // "내위치" 클릭 후 상단 옵션 표시
  int _searchRequestSeq = 0;

  // 시트 내부에서 현재 위치 주소를 직접 로드 (내위치 탭 시 검색창 채움용)
  String? _localCurrentAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    // 칩 subtitle용 주소만 로드 — 검색창은 건드리지 않음
    final preloaded = widget.currentLocationAddress;
    if (preloaded != null && preloaded.isNotEmpty) {
      if (mounted) setState(() => _localCurrentAddress = preloaded);
      return;
    }
    try {
      final loc = await ref.read(locationProvider.future);
      if (loc == null || !mounted) return;
      final addr = await ApiService().reverseGeocode(loc.lat, loc.lng);
      if (mounted) setState(() => _localCurrentAddress = addr);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _isLoading = false; _myLocationSelected = false; });
      return;
    }
    final reqId = ++_searchRequestSeq;
    setState(() => _isLoading = true);
    try {
      // 지도 탭과 동일하게 "좌표 근처 우선 검색"을 사용
      final center = ref.read(mapCenterProvider);
      final loc = center == null ? await ref.read(locationProvider.future) : null;
      final lat = center?.lat ?? loc?.lat;
      final lng = center?.lng ?? loc?.lng;
      final results = await ApiService().searchPlaces(query.trim(), lat: lat, lng: lng);
      if (!mounted || reqId != _searchRequestSeq) return;
      setState(() { _results = results; _isLoading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('[location-picker] searchPlaces 실패: $e');
      if (!mounted || reqId != _searchRequestSeq) return;
      setState(() { _results = []; _isLoading = false; });
    }
  }

  // "내위치" 칩 클릭 → 현재 주소를 검색창에 채우고 검색 (이미 채워졌으면 GPS 바로 사용)
  void _onMyLocationChipTap() {
    final addr = _localCurrentAddress;
    if (addr != null && addr.isNotEmpty) {
      if (_searchController.text == addr && _myLocationSelected) {
        // 이미 현재 주소로 채워진 상태 → GPS 그대로 사용
        widget.onMyLocation();
        return;
      }
      _searchController.text = addr;
      setState(() { _myLocationSelected = true; });
      _onSearchChanged(addr);
      _searchFocus.requestFocus();
    } else {
      widget.onMyLocation();
    }
  }

  /// 빠른 선택 공통 — 박스 없는 플랫 텍스트 버튼 (아이콘 + 라벨, 중앙 정렬)
  Widget _quickAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  /// 행 사이 얇은 세로 구분선
  Widget _vHairline(bool isDark) => Container(
        width: 1,
        height: 14,
        color: isDark ? AppColors.darkCardBorder : const Color(0xFFE8E8E8),
      );

  /// 미등록 집/회사 탭 → 즐겨찾기와 동일한 등록 화면 → 저장 후 바로 그 위치로 적용
  Future<void> _registerPlace(String kind, String label) async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => PlacePickerScreen(title: '$label 등록')),
    );
    if (picked == null || !mounted) return;
    await PlaceService.set(kind, picked);
    if (!mounted) return;
    setState(() {}); // 칩 활성화 반영
    widget.onSearchResult({
      'name': (picked['name'] ?? '').toString(),
      'address': (picked['address'] ?? '').toString(),
      'lat': picked['lat'],
      'lng': picked['lng'],
    });
  }

  /// 집/회사 바로가기 — PlaceService 등록 여부에 따라 활성(컬러)/비활성(회색).
  Widget _placeItem(String kind, String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = PlaceService.get(kind);
    final registered = p != null;
    final active = isDark ? AppColors.gasBlue : AppColors.gasBlueDark;
    final mutedFg = isDark ? AppColors.darkTextMuted : const Color(0xFFB5BCC6);
    return _quickAction(
      icon: icon,
      color: registered ? active : mutedFg,
      onTap: registered
          ? () => widget.onSearchResult({
                'name': (p['name'] ?? '').toString(),
                'address': (p['address'] ?? '').toString(),
                'lat': p['lat'],
                'lng': p['lng'],
              })
          : () => _registerPlace(kind, label),
      child: Text(
        registered ? (p['name'] ?? label).toString() : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: registered
              ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
              : mutedFg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.isOrigin ? '출발지 설정' : '목적지 설정',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextPrimary : null,
                ),
              ),
            ),
            // ① 검색 필드 (상단)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (v) {
                  if (_myLocationSelected) setState(() => _myLocationSelected = false);
                  _onSearchChanged(v);
                },
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.darkTextPrimary : null,
                ),
                decoration: InputDecoration(
                  hintText: widget.isOrigin ? '출발지 검색' : '목적지 검색',
                  hintStyle: TextStyle(
                    color: isDark ? AppColors.darkTextMuted : const Color(0xFFBBBBBB),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDark ? AppColors.darkTextSecondary : const Color(0xFF999999),
                    size: 20,
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.darkCard : const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // ② 빠른 선택 — 플랫 텍스트 버튼 2줄 (내위치·지도선택 / 집·회사), 박스 없이 헤어라인 구분
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  Expanded(
                    child: _quickAction(
                      icon: Icons.my_location_rounded,
                      color: kPrimary,
                      onTap: _onMyLocationChipTap,
                      child: const Text('내위치',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kPrimary)),
                    ),
                  ),
                  _vHairline(isDark),
                  Expanded(
                    child: _quickAction(
                      icon: Icons.map_outlined,
                      color: const Color(0xFF378ADD),
                      onTap: widget.onMapPick,
                      child: const Text('지도에서 선택',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF378ADD))),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFF0F0F0)),
            // ②-1 집/회사 바로가기 — 등록=컬러+즉시 설정, 미등록=회색
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  Expanded(child: _placeItem('home', '집', Icons.home_rounded)),
                  _vHairline(isDark),
                  Expanded(child: _placeItem('work', '회사', Icons.business_rounded)),
                ],
              ),
            ),
            const Divider(height: 1),
            // 검색 결과
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
                  : _searchController.text.isEmpty && !_myLocationSelected
                      ? (widget.searchHistoryItems.isEmpty
                          ? const Center(
                              child: Text('장소명, 주소를 입력하세요',
                                  style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB))))
                          : ListView.separated(
                              itemCount: widget.searchHistoryItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                              itemBuilder: (_, i) {
                                final h = widget.searchHistoryItems[i];
                                final name = h['name']?.toString() ?? '';
                                final address = h['address']?.toString() ?? '';
                                return ListTile(
                                  leading: const Icon(Icons.history_rounded, color: Color(0xFF999999), size: 20),
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: address.isNotEmpty
                                      ? Text(
                                          address,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  onTap: () => widget.onSearchResult(h),
                                );
                              },
                            ))
                      : _results.isEmpty && !_myLocationSelected
                          ? const Center(
                              child: Text('검색 결과가 없습니다',
                                  style: TextStyle(fontSize: 14, color: Color(0xFF999999))))
                          : ListView.builder(
                          itemCount: _results.length + (_myLocationSelected ? 1 : 0),
                          itemBuilder: (_, i) {
                            // 내위치 클릭 후 상단에 "현재 위치 그대로 사용" 옵션
                            if (_myLocationSelected && i == 0) {
                              return Column(
                                children: [
                                  ListTile(
                                    leading: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        color: kPrimaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.my_location_rounded,
                                          color: kPrimary, size: 18),
                                    ),
                                    title: const Text('현재 위치 사용',
                                        style: TextStyle(fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: kPrimary)),
                                    subtitle: widget.currentLocationAddress != null
                                        ? Text(widget.currentLocationAddress!,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? AppColors.darkTextSecondary : const Color(0xFF888888)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)
                                        : null,
                                    onTap: widget.onMyLocation,
                                  ),
                                  if (_results.isNotEmpty)
                                    const Divider(height: 1, indent: 56),
                                ],
                              );
                            }
                            final r = _results[i - (_myLocationSelected ? 1 : 0)];
                            final category = r['category']?.toString();
                            final dist = r['distance'];
                            final distStr = dist != null
                                ? formatDistance((dist as num).toDouble())
                                : null;
                            return Column(
                              children: [
                                InkWell(
                                  onTap: () => widget.onSearchResult(r),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.place_outlined, color: kPrimary, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(r['name']?.toString() ?? '',
                                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis),
                                                  ),
                                                  if (category != null && category.isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    Text(category,
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: isDark ? AppColors.darkTextSecondary : const Color(0xFF888888))),
                                                  ],
                                                  if (distStr != null) ...[
                                                    const SizedBox(width: 6),
                                                    Text(distStr,
                                                        style: const TextStyle(fontSize: 11, color: Color(0xFF1D6FE0))),
                                                  ],
                                                ],
                                              ),
                                              if ((r['address']?.toString() ?? '').isNotEmpty)
                                                Text(r['address'].toString(),
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: isDark ? AppColors.darkTextMuted : const Color(0xFF999999)),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (i < _results.length - 1 + (_myLocationSelected ? 1 : 0))
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          },
                        ),
              ),
          ],
        ),
      ),
    );
  }
}
