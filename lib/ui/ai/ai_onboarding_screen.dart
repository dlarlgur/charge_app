import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'ai_vehicle_list_screen.dart';
import 'ai_vehicle_setup_screen.dart';

const _kPrimary = Color(0xFF1D9E75);

class AiOnboardingScreen extends StatefulWidget {
  const AiOnboardingScreen({super.key});

  @override
  State<AiOnboardingScreen> createState() => _AiOnboardingScreenState();
}

class _AiOnboardingScreenState extends State<AiOnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const _kTotal = 4;

  void _next() {
    if (_page < _kTotal - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goToSetup();
    }
  }

  void _goToSetup() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiVehicleSetupScreen()),
    );
    if (!mounted) return;
    // 저장 완료한 경우에만 차량 목록으로 이동 (뒤로가기면 온보딩으로 복귀)
    if (saved == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AiVehicleListScreen(isFromOnboarding: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  // 1. 진짜 이득인 주유소 (우회 비용 계산)
                  _HeroPage(
                    lightIconBg: Color(0xFFE1F5EE),
                    icon: Icons.alt_route_rounded,
                    iconColor: _kPrimary,
                    title: '그냥 싼 주유소 말고,\n진짜 이득인 주유소',
                    desc: '경로에서 조금 벗어나도 훨씬 싼 주유소가 있다면?\n우회 비용까지 계산해서 진짜 절약을 알려드려요.',
                  ),
                  // 2. 충전소도 똑똑하게 — SOC 기반 추천
                  _HeroPage(
                    lightIconBg: Color(0xFFE9F8F0),
                    icon: Icons.ev_station_rounded,
                    iconColor: _kPrimary,
                    title: '전기차도 마찬가지,\n꼭 필요한 충전소만',
                    desc: '배터리 잔량과 주행 거리를 계산해\n경로상 휴게소·충전소를 우선 추천해요.',
                  ),
                  // 3. AI 비교 분석
                  _HeroPage(
                    lightIconBg: Color(0xFFFAEEDA),
                    icon: Icons.balance_rounded,
                    iconColor: Color(0xFFBA7517),
                    title: '비교는 AI가,\n선택은 내가',
                    desc: '최저가·우회 추천을 거리·연료비·시간까지\n한눈에 비교해서 보여드려요.',
                  ),
                  // 4. 차량 등록으로 시작
                  _HeroPage(
                    lightIconBg: Color(0xFFE6F1FB),
                    icon: Icons.directions_car_rounded,
                    iconColor: Color(0xFF378ADD),
                    title: '내연기관차도, 전기차도\n바로 시작!',
                    desc: '차량 타입을 선택하고 기본 정보를 입력하세요.\n주유·충전 최적 경로를 자동으로 분석합니다.',
                  ),
                ],
              ),
            ),
            _DotsIndicator(count: _kTotal, current: _page),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _page < _kTotal - 1 ? '다음' : '차량 정보 입력하기',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

// ─── 히어로 페이지 ────────────────────────────────────────────────────────────

class _HeroPage extends StatelessWidget {
  final Color lightIconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;

  const _HeroPage({
    required this.lightIconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 다크 모드에서는 브랜드 색을 옅게 깐 배경(8% alpha) 으로 통일 — 라이트의 파스텔 톤이 다크 bg 위에서 너무 밝게 튀는 문제 해소.
    final iconBg = isDark ? iconColor.withValues(alpha: 0.16) : lightIconBg;
    final titleColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final descColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 60, color: iconColor),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: titleColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: descColor,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 점 인디케이터 ─────────────────────────────────────────────────────────────

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? AppColors.darkCardBorder : const Color(0xFFE0E0E0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? _kPrimary : inactiveColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
