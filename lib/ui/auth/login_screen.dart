import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/app_dialog.dart';
import '../../core/util/app_toast.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_data_sync.dart';
import '../../providers/providers.dart';
import '../widgets/login_bottom_banner.dart';
import '../widgets/policy_sheet.dart';
import 'signup_complete_screen.dart';

/// 소셜 로그인 화면. 카카오 / 네이버 / 구글.
/// [gate]=true 면 첫 진입 게이트 모드: 성공/게스트 시 pop 대신 /permission 전진,
/// 하단 "게스트로 시작하기" 노출, 뒤로가기 차단.
class LoginScreen extends ConsumerStatefulWidget {
  final bool gate;
  const LoginScreen({super.key, this.gate = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  // 간편로그인 노출 여부(콘솔 원격설정). null=로딩 중(버튼 대신 로더 → 끄는 버튼 깜빡임 방지).
  Map<String, bool>? _enabled;

  // 약관 문구의 링크 탭 — TextSpan recognizer 는 위젯 수명과 함께 dispose 해야 한다
  // (build 마다 새로 만들면 누수).
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _openConsentDoc('terms');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openConsentDoc('privacy');
    AuthService.fetchEnabledProviders().then((m) {
      if (mounted) setState(() => _enabled = m);
    });
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _onProvider(String provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(authProvider.notifier).login(provider);
      if (!mounted) return;
      if (r.ok) {
        final user = ref.read(authProvider);
        // 미완성(닉네임·약관동의 전) 계정이면 가입완료 화면 강제.
        if (user != null && !user.signupCompleted) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SignupCompleteScreen(user: user),
          ));
          if (!mounted) return;
          // 가입완료 화면에서 취소(로그아웃)했으면 로그인 화면 유지.
          if (ref.read(authProvider) == null) {
            setState(() => _busy = false);
            return;
          }
        }
        // 회원 데이터 동기화: 서버에 있으면 로컬 적용(union)+알람 재구독, 없으면 로컬 이관.
        await UserDataSync.run();
        if (!mounted) return;
        // 박스에 복원된 값을 provider 상태로 반영 (차종/유종·즐겨찾기 즉시 갱신).
        ref.read(settingsProvider.notifier).reload();
        ref.read(gasFilterProvider.notifier).reload(); // 홈 유종 필터도 복원값 반영
        ref.read(favoritesProvider.notifier).refresh();
        if (widget.gate) {
          context.go('/permission');
        } else {
          Navigator.of(context).pop(true);
        }
        return;
      }
      // 사용자가 취소했거나 토큰 못 받음 — 조용히 화면 유지.
      setState(() => _busy = false);
    } on EmailInUseException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showEmailInUse(e.provider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, '로그인에 실패했어요. 잠시 후 다시 시도해주세요.', isError: true);
    }
  }

  void _showEmailInUse(String provider) {
    const names = {
      'kakao': '카카오',
      'naver': '네이버',
      'google': '구글',
      'apple': '애플'
    };
    final name = names[provider] ?? '다른 소셜';
    showAppDialog<void>(
      context,
      icon: Icons.mark_email_read_rounded,
      title: '이미 가입된 이메일',
      message: '이 이메일은 이미 $name 계정으로 가입돼 있어요.\n$name 로그인을 이용해주세요.',
      primaryLabel: '확인',
    );
  }

  Future<void> _startGuest() async {
    // 스크롤 안전한 공용 다이얼로그 재사용(작은 화면·큰 폰트 오버플로 방지).
    final proceed = await showAppDialog<bool>(
      context,
      icon: Icons.devices_other_rounded,
      title: '게스트로 시작할까요?',
      message: '게스트는 차량 정보·즐겨찾기·설정이\n이 기기에만 저장돼요.\n'
          '기기를 바꾸거나 앱을 지우면 복구할 수 없어요.',
      primaryLabel: '회원가입하고 시작',
      primaryValue: false,
      secondaryLabel: '게스트로 계속하기',
      secondaryValue: true,
    );
    if (proceed != true || !mounted) return;
    ref.read(settingsProvider.notifier).markGuestStarted();
    if (mounted) context.go('/permission');
  }

  /// 약관 문구의 '이용약관'/'개인정보처리방침' 탭 — 부트스트랩 동의 문서로 연결.
  /// 문서 링크가 없으면(원격설정 미구성) 탭만 무동작 — 문구는 그대로 보인다.
  void _openConsentDoc(String key) {
    final docs = DkswCore.signupConsents.where((c) => c.key == key).toList();
    if (docs.isEmpty) return;
    final url = docs.first.viewUrl;
    if (url == null || url.isEmpty) return;
    showPolicySheet(context, url: url, title: docs.first.title);
  }

  @override
  Widget build(BuildContext context) {
    // 이 화면은 앱 첫 진입(순백 미니멀 시안) 전용이라 다크 대응을 하지 않는다 —
    // 시스템 테마와 무관하게 항상 라이트로 그린다(형 확정 2026-08-20).
    final size = MediaQuery.of(context).size;
    // 작은 화면(높이 700 미만)에서 로고·헤드라인 축소 — 오버플로 대신 비율 축소.
    final compact = size.height < 700;
    final logoSize = compact ? 92.0 : 120.0;
    final headlineSize = compact ? 27.0 : 32.0;

    const textPrimary = AppColors.lightTextPrimary;
    const textSecondary = AppColors.lightTextSecondary;
    const muted = AppColors.lightTextMuted;

    // 배경 — 상단 순백을 62%까지 유지하다 아주 옅은 청록으로.
    const bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.loginHeroTop,
        AppColors.loginHeroTop,
        AppColors.loginHeroBottom,
      ],
      stops: [0.0, 0.62, 1.0],
    );

    return PopScope(
      canPop: !widget.gate,
      // 이 화면만 항상 라이트라, 상태바 아이콘도 여기서 강제로 어둡게 잡는다.
      // 앱 전역(main.dart)은 statusBarColor 만 투명으로 두고 밝기를 안 정해서,
      // 시스템이 다크 모드면 iOS 가 흰 글자 상태바를 그린다 → 순백 배경에서 실종.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: AppColors.loginHeroTop,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: bgGradient),
            // 글로우는 화면 밖으로 걸치게 두고 잘라낸다(블러 없이 radial 만으로).
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    top: -160,
                    left: -140,
                    child: _glow(AppColors.gasBlue, 460, 0.30),
                  ),
                  Positioned(
                    top: 120,
                    right: -180,
                    child: _glow(AppColors.evGreen, 440, 0.26),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        if (widget.gate)
                          const SizedBox(height: 56)
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                              child: IconButton(
                                icon: Icon(Icons.close_rounded,
                                    color: textSecondary),
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).maybePop(),
                              ),
                            ),
                          ),
                        // ── 히어로 ── 로고 → 헤드라인 → 서브카피 (중앙 정렬)
                        // Spacer(flex) 와 Flexible 을 같이 쓰면 둘이 공간을 나눠 가져
                        // 히어로가 점만큼 줄어든다(2026-08-20 사고). 여백은 Expanded 가
                        // 통째로 갖고, 그 안에서 FittedBox 가 '넘칠 때만' 축소한다.
                        // 정렬은 시안의 10:14 비율에 맞춰 중앙보다 살짝 위로.
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: const Alignment(0, -0.15),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/halfNhalf.png',
                                    width: logoSize,
                                    height: logoSize,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                  const SizedBox(height: 30),
                                  Text(
                                    '주유부터 충전까지,\n한 번에.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: headlineSize,
                                      height: 1.25,
                                      fontWeight: FontWeight.w800,
                                      // 시안 -0.035em
                                      letterSpacing: headlineSize * -0.035,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    '로그인하면 차량 정보와 설정이\n기기를 바꿔도 그대로 유지돼요.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 14,
                                        height: 1.6,
                                        color: textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ── 소셜 버튼 (로직·순서 그대로) ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                          child: Column(
                            children: _enabled == null
                                ? const [
                                    SizedBox(
                                      height: 160,
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.4),
                                        ),
                                      ),
                                    ),
                                  ]
                                : [
                                    // Apple 심사 가이드라인 4.8 — 제3자 소셜로그인 제공 시
                                    // 'Apple로 로그인'을 동등 이상으로 노출 (iOS 한정, 최상단).
                                    if (Platform.isIOS &&
                                        (_enabled!['apple'] ?? true)) ...[
                                      _SocialButton(
                                        label: 'Apple로 시작하기',
                                        bg: Colors.black,
                                        fg: Colors.white,
                                        icon: Icons.apple,
                                        onTap: () => _onProvider('apple'),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    if (_enabled!['kakao'] ?? true) ...[
                                      _SocialButton(
                                        label: '카카오로 시작하기',
                                        bg: const Color(0xFFFEE500),
                                        fg: const Color(0xFF191600),
                                        // 공식 심볼 — 카카오 로그인 버튼 리소스에서 추출
                                        iconChild: Image.asset(
                                            'assets/social/kakao_symbol.png',
                                            width: 19,
                                            height: 19),
                                        onTap: () => _onProvider('kakao'),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    if (_enabled!['naver'] ?? true) ...[
                                      _SocialButton(
                                        label: '네이버로 시작하기',
                                        bg: const Color(0xFF03C75A),
                                        fg: Colors.white,
                                        iconChild: const Text('N',
                                            style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white)),
                                        onTap: () => _onProvider('naver'),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    if (_enabled!['google'] ?? true)
                                      _SocialButton(
                                        label: '구글로 시작하기',
                                        bg: Colors.white,
                                        fg: const Color(0xFF1F1F1F),
                                        border: const Color(0xFFDADCE0),
                                        // 공식 4색 G 로고 (Google Identity 배포 에셋)
                                        iconChild: Image.asset(
                                            'assets/social/google_g.png',
                                            width: 19,
                                            height: 19),
                                        onTap: () => _onProvider('google'),
                                      ),
                                  ],
                          ),
                        ),
                        // 로그인 배너 — 소셜 버튼 바로 아래 지면 (콘솔 제어, 없으면 높이 0)
                        const LoginBottomBanner(slot: 'social'),
                        // ── 게스트 진입 (게이트 모드에서만) ──
                        if (widget.gate)
                          SizedBox(
                            height: 52,
                            child: TextButton(
                              onPressed: _busy ? null : _startGuest,
                              style: TextButton.styleFrom(
                                foregroundColor: textSecondary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('게스트로 시작하기',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary)),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: textSecondary),
                                ],
                              ),
                            ),
                          ),
                        // ── 약관 ── '이용약관'/'개인정보처리방침'만 링크 톤 + 탭
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              28, widget.gate ? 2 : 10, 28, 14),
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                  fontSize: 11, height: 1.5, color: muted),
                              children: [
                                const TextSpan(text: '로그인 시 '),
                                TextSpan(
                                  text: '이용약관',
                                  style: TextStyle(
                                    color: textSecondary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: textSecondary,
                                  ),
                                  recognizer: _termsTap,
                                ),
                                const TextSpan(text: ' 및 '),
                                TextSpan(
                                  text: '개인정보처리방침',
                                  style: TextStyle(
                                    color: textSecondary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: textSecondary,
                                  ),
                                  recognizer: _privacyTap,
                                ),
                                const TextSpan(text: '에 동의하게 됩니다.'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // 로그인 배너 — 화면 하단 지면 (콘솔 제어, 없으면 높이 0)
                        const LoginBottomBanner(slot: 'bottom'),
                      ],
                    ),
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 배경 글로우 한 덩어리 — blur 없이 radial 만으로 (셰이더 비용 0).
  Widget _glow(Color color, double size, double centerAlpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.5,
            colors: [
              color.withValues(alpha: centerAlpha),
              color.withValues(alpha: centerAlpha / 3),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.45, 0.72],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final IconData? icon;
  final Widget? iconChild;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.border,
    this.icon,
    this.iconChild,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56, // 시안 스펙
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  border != null ? Border.all(color: border!, width: 1) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                          child: iconChild ?? Icon(icon, size: 21, color: fg)),
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
