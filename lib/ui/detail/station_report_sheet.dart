import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/util/app_toast.dart';
import '../../data/services/api_service.dart';

/// 주유소·충전소 정보 제보 바텀시트.
/// 카테고리 선택 → 카테고리별 구조화 입력 + 선택 메모 → 서버 제출(텔레그램 알림).
Future<void> showStationReportSheet(
  BuildContext context, {
  required String stationType, // 'gas' | 'ev'
  required String stationId,
  required String stationName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StationReportSheet(
      stationType: stationType,
      stationId: stationId,
      stationName: stationName,
    ),
  );
}

class _Cat {
  final String key;
  final String label;
  final IconData icon;
  const _Cat(this.key, this.label, this.icon);
}

const _gasCats = [
  _Cat('carwash', '세차장', Icons.local_car_wash_rounded),
  _Cat('hours', '영업시간', Icons.schedule_rounded),
  _Cat('store', '편의점', Icons.storefront_rounded),
  _Cat('maint', '경정비', Icons.build_rounded),
  _Cat('closed', '폐업·위치', Icons.wrong_location_rounded),
  _Cat('etc', '기타', Icons.more_horiz_rounded),
];

const _evCats = [
  _Cat('price', '요금', Icons.payments_rounded),
  _Cat('broken', '고장·불가', Icons.power_off_rounded),
  _Cat('closed', '폐쇄·위치', Icons.wrong_location_rounded),
  _Cat('access', '이용정보', Icons.info_rounded),
  _Cat('etc', '기타', Icons.more_horiz_rounded),
];

/// 상세 화면 정보 섹션에 두는 제보 진입 버튼 (톤다운 카드형).
class StationReportButton extends StatelessWidget {
  const StationReportButton({
    super.key,
    required this.stationType,
    required this.stationId,
    required this.stationName,
    this.margin,
  });
  final String stationType;
  final String stationId;
  final String stationName;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isEv = stationType == 'ev';
    final accent = isEv ? const Color(0xFF10B981) : const Color(0xFF2563EB);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    return Container(
      margin: margin ?? const EdgeInsets.only(top: 12),
      child: Material(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showStationReportSheet(context,
              stationType: stationType, stationId: stationId, stationName: stationName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.campaign_rounded, color: accent, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('정보가 틀렸거나 빠졌나요?',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.2)),
                      const SizedBox(height: 1),
                      Text(isEv ? '요금·고장 등 알려주시면 확인할게요' : '세차·영업시간 등 알려주시면 확인할게요',
                          style: TextStyle(fontSize: 11.5, color: muted)),
                    ],
                  ),
                ),
                Text('제보', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
                Icon(Icons.chevron_right_rounded, color: accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationReportSheet extends StatefulWidget {
  const _StationReportSheet({
    required this.stationType,
    required this.stationId,
    required this.stationName,
  });
  final String stationType;
  final String stationId;
  final String stationName;

  @override
  State<_StationReportSheet> createState() => _StationReportSheetState();
}

class _StationReportSheetState extends State<_StationReportSheet> {
  bool get _isEv => widget.stationType == 'ev';
  Color get _accent => _isEv ? const Color(0xFF10B981) : const Color(0xFF2563EB);
  List<_Cat> get _cats => _isEv ? _evCats : _gasCats;

  String? _cat;
  // 카테고리별 입력 상태
  String? _washAvail; // yes | no
  String? _washType; // self | auto | touchless | other
  bool? _is24h;
  String? _storeAvail;
  String? _maintAvail;
  String? _closedKind; // closed | location
  final _infoCtrl = TextEditingController(); // price/access/broken
  final _hoursCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _infoCtrl.dispose();
    _hoursCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _selectCat(String key) {
    setState(() {
      _cat = key;
      // 다른 카테고리 선택 시 입력 초기화(혼선 방지)
      _washAvail = _washType = _storeAvail = _maintAvail = _closedKind = null;
      _is24h = null;
      _infoCtrl.clear();
      _hoursCtrl.clear();
    });
  }

  bool get _canSubmit {
    if (_submitting || _cat == null) return false;
    switch (_cat) {
      case 'carwash':
        return _washAvail != null;
      case 'hours':
        return _is24h != null;
      case 'store':
        return _storeAvail != null;
      case 'maint':
        return _maintAvail != null;
      case 'closed':
        return _closedKind != null;
      case 'price':
      case 'access':
      case 'broken':
        return _infoCtrl.text.trim().isNotEmpty;
      case 'etc':
        return _memoCtrl.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  Map<String, dynamic>? _buildDetail() {
    switch (_cat) {
      case 'carwash':
        return {'available': _washAvail, if (_washAvail == 'yes' && _washType != null) 'type': _washType};
      case 'hours':
        return {'is24h': _is24h, if (_is24h == false && _hoursCtrl.text.trim().isNotEmpty) 'hours': _hoursCtrl.text.trim()};
      case 'store':
        return {'available': _storeAvail};
      case 'maint':
        return {'available': _maintAvail};
      case 'closed':
        return {'kind': _closedKind};
      case 'price':
      case 'access':
        return {'info': _infoCtrl.text.trim()};
      case 'broken':
        return {'note': _infoCtrl.text.trim()};
      default:
        return null;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final ok = await ApiService().submitReport(
        stationType: widget.stationType,
        stationId: widget.stationId,
        stationName: widget.stationName,
        category: _cat!,
        detail: _buildDetail(),
        memo: _memoCtrl.text,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        showAppToast(context, '제보 감사합니다! 확인 후 반영할게요 🙏');
      } else {
        setState(() => _submitting = false);
        showAppToast(context, '제보 전송에 실패했어요. 잠시 후 다시 시도해주세요.', isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(context, '네트워크 오류로 전송에 실패했어요.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF161B22) : Colors.white;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
    final line = isDark ? const Color(0x22FFFFFF) : const Color(0xFFE8ECF0);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // 헤더
            Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.campaign_rounded, color: _accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('정보 제보',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.4)),
                      const SizedBox(height: 2),
                      Text(widget.stationName,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _label('어떤 정보인가요?', muted),
            const SizedBox(height: 10),
            _categoryGrid(isDark, ink, muted, line),
            // 카테고리별 입력
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _cat == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _inputForCat(isDark, ink, muted, line),
                    ),
            ),
            const SizedBox(height: 18),
            _label('추가로 알려줄 내용 (선택)', muted),
            const SizedBox(height: 8),
            _field(_memoCtrl, '예) 주말엔 세차 안 해요',
                isDark: isDark, ink: ink, muted: muted, line: line, maxLines: 2,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 20),
            _submitButton(),
          ],
        ),
      ),
    );
  }

  Widget _label(String t, Color muted) =>
      Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: muted, letterSpacing: -0.2));

  Widget _categoryGrid(bool isDark, Color ink, Color muted, Color line) {
    final w = (MediaQuery.of(context).size.width - 40 - 20) / 3; // padding 20*2, gap 10*2
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _cats.map((c) {
        final sel = _cat == c.key;
        return SizedBox(
          width: w,
          child: GestureDetector(
            onTap: () => _selectCat(c.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: sel ? _accent.withValues(alpha: 0.10) : (isDark ? const Color(0x0DFFFFFF) : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? _accent : line, width: sel ? 1.5 : 1),
              ),
              child: Column(
                children: [
                  Icon(c.icon, size: 24, color: sel ? _accent : muted),
                  const SizedBox(height: 7),
                  Text(c.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          color: sel ? _accent : ink)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _inputForCat(bool isDark, Color ink, Color muted, Color line) {
    switch (_cat) {
      case 'carwash':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('세차장이 있나요?', muted),
            const SizedBox(height: 8),
            _segmented(const ['있음', '없음'], const ['yes', 'no'], _washAvail,
                (v) => setState(() { _washAvail = v; if (v == 'no') _washType = null; }), ink, line),
            if (_washAvail == 'yes') ...[
              const SizedBox(height: 14),
              _label('세차 종류', muted),
              const SizedBox(height: 8),
              _chips(const ['셀프', '자동', '터치리스', '기타'], const ['self', 'auto', 'touchless', 'other'],
                  _washType, (v) => setState(() => _washType = v), ink, line),
            ],
          ],
        );
      case 'hours':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('영업시간이 어떻게 되나요?', muted),
            const SizedBox(height: 8),
            _segmented(const ['24시간', '아니요'], const ['24', 'no'],
                _is24h == null ? null : (_is24h! ? '24' : 'no'),
                (v) => setState(() => _is24h = v == '24'), ink, line),
            if (_is24h == false) ...[
              const SizedBox(height: 12),
              _field(_hoursCtrl, '예) 07:00 ~ 23:00',
                  isDark: isDark, ink: ink, muted: muted, line: line),
            ],
          ],
        );
      case 'store':
        return _availBlock('편의점이 있나요?', _storeAvail, (v) => setState(() => _storeAvail = v), muted, ink, line);
      case 'maint':
        return _availBlock('경정비가 되나요?', _maintAvail, (v) => setState(() => _maintAvail = v), muted, ink, line);
      case 'closed':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('무엇이 잘못됐나요?', muted),
            const SizedBox(height: 8),
            _segmented(
                _isEv ? const ['없어졌어요', '위치가 달라요'] : const ['폐업했어요', '위치가 달라요'],
                const ['closed', 'location'], _closedKind,
                (v) => setState(() => _closedKind = v), ink, line),
          ],
        );
      case 'price':
        return _infoBlock('요금 정보', '예) 급속 347원/kWh, 완속 250원', isDark, ink, muted, line);
      case 'access':
        return _infoBlock('이용 정보', '예) 주차요금 별도 · 야간 미운영 · 회원카드 필요', isDark, ink, muted, line);
      case 'broken':
        return _infoBlock('어떤 상태인가요?', '예) 2번 충전기 고장 · 케이블 손상', isDark, ink, muted, line);
      case 'etc':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x0DFFFFFF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('아래 메모에 자유롭게 적어주세요.', style: TextStyle(fontSize: 13, color: muted)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _availBlock(String q, String? val, ValueChanged<String> onSel, Color muted, Color ink, Color line) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(q, muted),
          const SizedBox(height: 8),
          _segmented(const ['있음', '없음'], const ['yes', 'no'], val, onSel, ink, line),
        ],
      );

  Widget _infoBlock(String t, String hint, bool isDark, Color ink, Color muted, Color line) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(t, muted),
          const SizedBox(height: 8),
          _field(_infoCtrl, hint, isDark: isDark, ink: ink, muted: muted, line: line, maxLines: 2,
              onChanged: (_) => setState(() {})),
        ],
      );

  // 세그먼트(2~3지선다)
  Widget _segmented(List<String> labels, List<String> values, String? sel, ValueChanged<String> onSel, Color ink, Color line) {
    return Row(
      children: List.generate(labels.length, (i) {
        final s = sel == values[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
            child: GestureDetector(
              onTap: () => onSel(values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: s ? _accent : line, width: s ? 1.5 : 1),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: s ? Colors.white : ink)),
              ),
            ),
          ),
        );
      }),
    );
  }

  // 칩(여러개 중 하나)
  Widget _chips(List<String> labels, List<String> values, String? sel, ValueChanged<String> onSel, Color ink, Color line) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: List.generate(labels.length, (i) {
        final s = sel == values[i];
        return GestureDetector(
          onTap: () => onSel(values[i]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: s ? _accent.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: s ? _accent : line, width: s ? 1.5 : 1),
            ),
            child: Text(labels[i],
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: s ? _accent : ink)),
          ),
        );
      }),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {required bool isDark, required Color ink, required Color muted, required Color line,
      int maxLines = 1, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14.5, color: ink, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: muted.withValues(alpha: 0.8)),
        filled: true,
        fillColor: isDark ? const Color(0x0DFFFFFF) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }

  Widget _submitButton() {
    final enabled = _canSubmit;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          disabledBackgroundColor: _accent.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
            : const Text('제보하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
      ),
    );
  }
}
