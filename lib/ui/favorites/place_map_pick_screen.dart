import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/api_service.dart';

/// 집/회사 등록 — 지도에서 위치 선택. 중앙 크로스헤어 고정, 카메라 멈추면
/// 역지오코딩으로 주소 표시, [이 위치로 설정] 시 {name, address, lat, lng} 반환.
class PlaceMapPickScreen extends StatefulWidget {
  final String title; // '집 위치 선택' / '회사 위치 선택'
  const PlaceMapPickScreen({super.key, required this.title});

  @override
  State<PlaceMapPickScreen> createState() => _PlaceMapPickScreenState();
}

class _PlaceMapPickScreenState extends State<PlaceMapPickScreen> {
  NaverMapController? _controller;
  NLatLng? _target;
  String? _address;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onIdle() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final c = _controller;
      if (c == null || !mounted) return;
      try {
        final pos = await c.getCameraPosition();
        if (!mounted) return;
        setState(() {
          _target = pos.target;
          _resolving = true;
        });
        final addr = await ApiService()
            .reverseGeocode(pos.target.latitude, pos.target.longitude);
        if (!mounted) return;
        setState(() {
          _address = (addr != null && addr.isNotEmpty) ? addr : null;
          _resolving = false;
        });
      } catch (_) {
        if (mounted) setState(() => _resolving = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canConfirm = _target != null && !_resolving;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(37.5665, 126.9780),
                zoom: 15,
              ),
              locationButtonEnable: true,
            ),
            onMapReady: (c) {
              _controller = c;
              _onIdle();
            },
            onCameraIdle: _onIdle,
          ),
          // 중앙 크로스헤어 핀 (끝이 지도 중심을 가리키도록 살짝 올림)
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 34),
                child: Icon(Icons.location_on_rounded,
                    size: 40, color: Color(0xFFE0533D)),
              ),
            ),
          ),
          // 하단 주소 + 확정 버튼
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppColors.darkCardBorder
                          : const Color(0xFFE8ECF0),
                      width: 0.8),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _resolving
                          ? '주소 확인 중...'
                          : (_address ?? '지도를 움직여 위치를 선택하세요'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        onPressed: canConfirm
                            ? () => Navigator.pop(context, {
                                  'name': _address ?? '선택한 위치',
                                  'address': _address ?? '',
                                  'lat': _target!.latitude,
                                  'lng': _target!.longitude,
                                })
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              isDark ? AppColors.gasBlue : AppColors.gasBlueDark,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('이 위치로 설정',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
