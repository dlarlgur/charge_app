import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils/helpers.dart';
import '../../data/services/watch_service.dart';
import '../detail/ev_detail_screen.dart';

class WatchSessionBar extends StatefulWidget {
  const WatchSessionBar({super.key});

  @override
  State<WatchSessionBar> createState() => _WatchSessionBarState();
}

class _WatchSessionBarState extends State<WatchSessionBar> {
  Timer? _timer;
  bool _extending = false;

  static const _kBlue = Color(0xFF1D6FE0);
  static const _kBlueLight = Color(0xFFEEF4FF);

  @override
  void initState() {
    super.initState();
    WatchService().sessionChanged.addListener(_onSessionChanged);
    _startTimer();
  }

  @override
  void dispose() {
    WatchService().sessionChanged.removeListener(_onSessionChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (WatchService().session == null) return;
    // 진입 즉시 최신 자리 수 조회
    WatchService().refreshAvail();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      WatchService().refreshAvail();
    });
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return '만료됨';
    return fmtMin(d.inMinutes.clamp(0, 9999));
  }

  Future<void> _extend() async {
    if (_extending) return;
    setState(() => _extending = true);
    final ok = await WatchService().extend();
    if (mounted) {
      setState(() => _extending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연장에 실패했어요. 다시 시도해주세요.')),
        );
      }
    }
  }

  void _openDetail() {
    final statId = WatchService().session?.statId;
    if (statId == null) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EvDetailScreen(stationId: statId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = WatchService().session;
    if (session == null) return const SizedBox.shrink();

    final remaining = session.remaining;
    final timeStr = _formatRemaining(remaining);
    final avail = session.currentAvail;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 4,
          shadowColor: _kBlue.withOpacity(0.18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBlue.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  // ── 왼쪽: 아이콘 + 텍스트 ──
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: _kBlueLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar_rounded, size: 18, color: _kBlue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: _kBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              '자리 변동 알림 중',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _kBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          session.stationName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          avail != null
                              ? '$timeStr 남음  ·  현재 ${avail}자리'
                              : '$timeStr 남음',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // ── 오른쪽: 액션 버튼들 ──
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SmallBtn(
                            label: _extending ? '...' : '+30분',
                            color: _kBlue,
                            filled: false,
                            onTap: _extending ? null : _extend,
                          ),
                          const SizedBox(width: 5),
                          _SmallBtn(
                            label: '상세',
                            color: _kBlue,
                            filled: false,
                            onTap: _openDetail,
                          ),
                          const SizedBox(width: 5),
                          _SmallBtn(
                            label: '끄기',
                            color: const Color(0xFF888888),
                            filled: false,
                            onTap: () => WatchService().stop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _SmallBtn({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
