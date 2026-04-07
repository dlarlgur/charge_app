import 'package:flutter/material.dart';

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

  void _next() {
    if (_page < 2) {
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  // 1. 진짜 이득인 주유소
                  _HeroPage(
                    iconBg: Color(0xFFE1F5EE),
                    icon: Icons.schedule_rounded,
                    iconColor: _kPrimary,
                    title: '그냥 싼 주유소 말고,\n진짜 이득인 주유소',
                    desc: '경로에서 조금 벗어나도 훨씬 싼 주유소가 있다면?\n우회 비용까지 계산해서 진짜 절약을 알려드려요.',
                  ),
                  // 2. 비교는 AI가
                  _HeroPage(
                    iconBg: Color(0xFFFAEEDA),
                    icon: Icons.space_dashboard_rounded,
                    iconColor: Color(0xFFBA7517),
                    title: '비교는 AI가,\n선택은 내가',
                    desc: '경로상 최저가 주유소와 우회 추천 주유소를\n우회 거리·연료비·시간까지 비교 분석합니다.',
                  ),
                  // 3. 내연기관 + 전기차 모두 지원
                  _HeroPage(
                    iconBg: Color(0xFFE6F1FB),
                    icon: Icons.directions_car_rounded,
                    iconColor: Color(0xFF378ADD),
                    title: '내연기관차도, 전기차도\n바로 시작!',
                    desc: '차량 타입을 선택하고 기본 정보를 입력하세요.\n주유·충전 최적 경로를 자동으로 분석합니다.',
                  ),
                ],
              ),
            ),
            _DotsIndicator(count: 3, current: _page),
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
                    _page < 2 ? '다음' : '차량 정보 입력하기',
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
  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;

  const _HeroPage({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1a1a1a),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF888888),
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
            color: active ? _kPrimary : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
