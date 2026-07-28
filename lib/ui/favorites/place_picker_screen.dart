import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/api_service.dart';
import 'place_map_pick_screen.dart';

/// 집/회사 장소 선택 — 지도 탭과 동일한 장소 검색(searchPlaces) 재사용.
/// 선택 시 {name, address, lat, lng} 반환.
class PlacePickerScreen extends StatefulWidget {
  final String title; // '집 등록' / '회사 등록'
  const PlacePickerScreen({super.key, required this.title});

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await ApiService().searchPlaces(q.trim());
      if (mounted) setState(() { _results = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _results = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '장소·주소 검색',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: isDark ? AppColors.darkCard : const Color(0xFFF1F3F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await Navigator.of(context).push<Map<String, dynamic>>(
                    MaterialPageRoute(
                        builder: (_) => PlaceMapPickScreen(title: widget.title)),
                  );
                  if (picked != null && context.mounted) Navigator.pop(context, picked);
                },
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('지도에서 선택', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final p = _results[i];
                final name = (p['name'] ?? '').toString();
                final addr = (p['address'] ?? '').toString();
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.place_outlined, size: 20, color: muted),
                  title: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(addr,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted)),
                  onTap: () => Navigator.pop(context, {
                    'name': name,
                    'address': addr,
                    'lat': (p['lat'] as num).toDouble(),
                    'lng': (p['lng'] as num).toDouble(),
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
