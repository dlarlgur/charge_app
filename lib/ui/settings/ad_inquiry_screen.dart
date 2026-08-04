import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

/// 광고 문의 — 지면 소개 + 문의처.
///
/// 단가는 넣지 않는다. 초기 매체는 상대·기간에 따라 조정 여지가 필요하고,
/// 한번 공개한 가격은 되돌리기 어렵다. 규모와 지면만 보여주고 협의로 넘긴다.
///
/// 이용자 수치는 서버 실측(/ad-inquiry/stats)으로 현행화 — 하드코딩 수치가
/// 낡아서 실제보다 작게/크게 보이는 일 방지. 실패 시 아래 폴백 상수 유지.
class AdInquiryScreen extends StatefulWidget {
  const AdInquiryScreen({super.key});

  @override
  State<AdInquiryScreen> createState() => _AdInquiryScreenState();
}

class _AdInquiryScreenState extends State<AdInquiryScreen> {
  static const _email = 'ghim2131@gmail.com';

  // 서버 조회 실패 시 폴백 (2026-08 실측: MAU 2,437 / 평균 DAU 246 / 차종 등록 2,057)
  String _mau = '2,400+';
  String _dau = '240+';
  String _vehicles = '2,000+';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final res = await Dio().get(
        '${ApiConstants.baseUrl}/ad-inquiry/stats',
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      final d = res.data;
      if (d is! Map || !mounted) return;
      final mau = _fmtStat(d['mau']);
      final dau = _fmtStat(d['dau']);
      final vehicles = _fmtStat(d['vehicles']);
      setState(() {
        if (mau != null) _mau = mau;
        if (dau != null) _dau = dau;
        if (vehicles != null) _vehicles = vehicles;
      });
    } catch (_) {
      // 폴백 상수 유지
    }
  }

  /// 2347 → '2,300+' 처럼 살짝 내림한 마케팅 표기.
  /// 0 이하/파싱 불가면 null — 폴백 상수를 덮어쓰지 않는다 ('0+' 노출 방지).
  static String? _fmtStat(dynamic v) {
    final n = (v is num) ? v.toInt() : int.tryParse('$v');
    if (n == null || n <= 0) return null;
    final step = n >= 10000
        ? 1000
        : n >= 1000
            ? 100
            : n >= 100
                ? 10
                : 1;
    final floored = (n ~/ step) * step;
    final s = floored.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return step == 1 ? s : '$s+';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('광고 문의')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
        children: [
          _hero(isDark),
          const SizedBox(height: 18),
          _sectionTitle('광고 지면', isDark),
          const SizedBox(height: 10),
          _placementsCard(context, isDark),
          const SizedBox(height: 18),
          _sectionTitle('이런 분께 맞아요', isDark),
          const SizedBox(height: 10),
          _fitChips(isDark),
          const SizedBox(height: 18),
          _sectionTitle('문의', isDark),
          const SizedBox(height: 10),
          _contactCard(context, isDark),
          const SizedBox(height: 12),
          Text(
            '단가와 소재 규격은 문의 주시면 제안서로 안내드려요. 집행 중에는 노출·클릭 리포트를 보내드립니다.',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted),
          ),
        ],
      ),
    );
  }

  Widget _hero(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF16324F), const Color(0xFF12283D)]
              : [const Color(0xFFEFF6FF), const Color(0xFFE0F2FE)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark
                ? AppColors.darkGasActiveBorder
                : AppColors.lightGasActiveBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('전기차 기름차에 광고하기',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary)),
          const SizedBox(height: 6),
          Text('주유소·충전소를 찾는 순간에 노출됩니다.',
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary)),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('월 이용자', _mau, isDark),
              _statDivider(isDark),
              _stat('일 이용자', _dau, isDark),
              _statDivider(isDark),
              _stat('차량 등록', _vehicles, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool isDark) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.gasBlue)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextSecondary)),
          ],
        ),
      );

  Widget _statDivider(bool isDark) => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.10),
      );

  Widget _sectionTitle(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color:
              isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary));

  // 설명은 한 줄로 — 규격·단가 같은 실무 정보는 문의 후 제안서에서 (화면이 조잡해짐).
  static const _placements = <_Placement>[
    _Placement(Icons.smartphone_rounded, '앱 실행 화면', '앱을 켤 때 전체 화면 1회 — 브랜드 각인',
        _PlacementKind.splash),
    _Placement(Icons.view_agenda_rounded, '홈 상단 배너', '목록 맨 위 고정 — 가장 많이 보는 자리',
        _PlacementKind.homeTop),
    _Placement(Icons.format_list_bulleted_rounded, '홈 목록 사이',
        '탐색 흐름 속에 자연스러운 카드형', _PlacementKind.homeList),
    _Placement(Icons.login_rounded, '로그인 화면', '노출은 적지만 정독하는 순간 — 반응률 최고',
        _PlacementKind.login),
    _Placement(Icons.local_gas_station_rounded, '주유소·충전소 상세',
        '방문 직전 사용자 — 세차·정비 맞춤', _PlacementKind.detail),
  ];

  /// 지면 목록 — 카드 하나에 행 분할 (앱 공통 문법). 행 탭 → 예시 미리보기 시트.
  Widget _placementsCard(BuildContext context, bool isDark) {
    final line = isDark ? AppColors.darkCardBorder : const Color(0xFFF0F3F6);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _placements.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, thickness: 1, color: line),
              ),
            InkWell(
              onTap: () => _showPlacementPreview(context, _placements[i]),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.gasBlue
                            .withValues(alpha: isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_placements[i].icon,
                          size: 17, color: AppColors.gasBlue),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_placements[i].title,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.lightTextPrimary)),
                          const SizedBox(height: 2),
                          Text(_placements[i].desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('예시',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted)),
                    Icon(Icons.chevron_right_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPlacementPreview(BuildContext context, _Placement p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _PlacementPreviewSheet(placement: p, isDark: isDark),
    );
  }

  /// 업종 칩 — 문장 나열 대신 한눈에 (형: 조잡함 정리).
  Widget _fitChips(bool isDark) {
    const items = <(IconData, String)>[
      (Icons.local_gas_station_rounded, '주유소 · 충전소'),
      (Icons.local_car_wash_rounded, '세차 · 정비 · 타이어'),
      (Icons.directions_car_rounded, '자동차 용품 · 보험'),
      (Icons.storefront_rounded, '지역 소상공인'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.lightCardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(it.$1, size: 15, color: AppColors.evGreen),
                const SizedBox(width: 7),
                Text(it.$2,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _contactCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이메일로 문의해 주세요',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary)),
          const SizedBox(height: 3),
          Text('업종 · 희망 지면 · 기간을 함께 적어주시면 더 빠르게 안내드려요.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.mail_outline_rounded,
                    size: 17,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(_email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: _email));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('이메일 주소를 복사했어요'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('주소 복사'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.lightCardBorder),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: _email,
                      query: 'subject=${Uri.encodeComponent('[전기차 기름차] 광고 문의')}'
                          '&body=${Uri.encodeComponent('업종:\n희망 지면:\n희망 기간:\n연락처:\n')}',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } else if (context.mounted) {
                      await Clipboard.setData(
                          const ClipboardData(text: _email));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('메일 앱이 없어 주소를 복사했어요')),
                      );
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('메일 쓰기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gasBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PlacementKind { splash, homeTop, homeList, login, detail }

class _Placement {
  const _Placement(this.icon, this.title, this.desc, this.kind);
  final IconData icon;
  final String title;
  final String desc;
  final _PlacementKind kind;
}

/// 지면 예시 시트 — 스크린샷 대신 앱 테마에 맞는 와이어프레임 목업.
/// 실제 화면 캡처는 유지보수(화면 바뀔 때마다 재촬영) 부담이라 도식으로.
class _PlacementPreviewSheet extends StatelessWidget {
  const _PlacementPreviewSheet({required this.placement, required this.isDark});

  final _Placement placement;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.gasBlue
                        .withValues(alpha: isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(placement.icon, size: 17, color: AppColors.gasBlue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(placement.title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(placement.desc,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary)),
            const SizedBox(height: 16),
            Center(child: _phoneFrame()),
            const SizedBox(height: 12),
            Center(
              child: Text('파란 영역에 광고가 노출됩니다',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 와이어프레임 목업 ──────────────────────────────────────

  Color get _bg => isDark ? const Color(0xFF0E1621) : const Color(0xFFF5F7FA);
  Color get _block =>
      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
  Color get _blockSoft =>
      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);

  Widget _phoneFrame() {
    return Container(
      width: 190,
      height: 320,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.18),
            width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: switch (placement.kind) {
          _PlacementKind.splash => _splashMock(),
          _PlacementKind.homeTop => _homeTopMock(),
          _PlacementKind.homeList => _homeListMock(),
          _PlacementKind.login => _loginMock(),
          _PlacementKind.detail => _detailMock(),
        },
      ),
    );
  }

  Widget _bar({double h = 12, double? w, Color? color, double r = 4}) =>
      Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: color ?? _block,
          borderRadius: BorderRadius.circular(r),
        ),
      );

  Widget _adSlot({double? h, bool expand = false, String label = '광고'}) {
    final slot = Container(
      height: h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.gasBlue.withValues(alpha: isDark ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gasBlue, width: 1.4),
      ),
      child: Center(
        child: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: AppColors.gasBlue)),
      ),
    );
    return expand ? Expanded(child: slot) : slot;
  }

  /// 앱 실행 화면 — 전면 광고 + 우상단 건너뛰기 + 하단 로고
  Widget _splashMock() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              _adSlot(h: double.infinity),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('건너뛰기',
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                  color: _block, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 6),
            _bar(h: 8, w: 60),
          ],
        ),
      ],
    );
  }

  /// 홈 상단 배너 — 검색바 아래 고정 배너 + 목록
  Widget _homeTopMock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(h: 20, r: 10),
        const SizedBox(height: 8),
        _adSlot(h: 34),
        const SizedBox(height: 8),
        for (var i = 0; i < 4; i++) ...[
          _listRowMock(),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  /// 홈 목록 사이 — 카드형 네이티브
  Widget _homeListMock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(h: 20, r: 10),
        const SizedBox(height: 8),
        _listRowMock(),
        const SizedBox(height: 6),
        _listRowMock(),
        const SizedBox(height: 6),
        _adSlot(h: 42),
        const SizedBox(height: 6),
        _listRowMock(),
        const SizedBox(height: 6),
        _listRowMock(),
      ],
    );
  }

  /// 로그인 화면 — 로고 + 소셜 버튼 + 하단 배너
  Widget _loginMock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _block, borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: _bar(h: 8, w: 80)),
        const Spacer(),
        _bar(h: 22, r: 11),
        const SizedBox(height: 6),
        _bar(h: 22, r: 11, color: _blockSoft),
        const SizedBox(height: 14),
        _adSlot(h: 44),
      ],
    );
  }

  /// 상세 화면 — 가격/정보 행 사이 광고 카드
  Widget _detailMock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(h: 16, w: 90),
        const SizedBox(height: 6),
        _bar(h: 8, w: 120, color: _blockSoft),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _blockSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(h: 8, w: 70),
              const SizedBox(height: 5),
              _bar(h: 8, w: 100),
              const SizedBox(height: 5),
              _bar(h: 8, w: 55),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _adSlot(h: 40),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _blockSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(h: 8, w: 90),
              const SizedBox(height: 5),
              _bar(h: 8, w: 60),
            ],
          ),
        ),
      ],
    );
  }

  /// 목록 행 목업 (아이콘 + 두 줄 텍스트)
  Widget _listRowMock() {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: _blockSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                color: _block, borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(h: 7, w: 70),
                const SizedBox(height: 4),
                _bar(h: 6, w: 45, color: _block),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
