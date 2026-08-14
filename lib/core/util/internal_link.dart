import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/cheer/cheer_screen.dart';
import '../../ui/cheer/garage_screen.dart';
import '../../ui/events/events_screen.dart';
import '../../ui/faq/faq_screen.dart';
import '../../ui/inbox/inbox_screen.dart';
import '../../ui/notices/notices_screen.dart';
import '../../ui/reports/fuel_report_screen.dart';
import '../../ui/reports/my_reports_screen.dart';
import '../../ui/settings/policies_screen.dart';
import '../../ui/settings/settings_screen.dart';

/// 콘솔이 지정한 '앱 내부 화면' 식별자를 실제 화면으로 잇는 단일 디스패처.
///
/// 콘솔에서 내부 이동을 지정하는 자리는 네 곳이고 형식이 모두 같다 —
/// house/팝업 광고는 `cta_type='internal'` + `cta_url='/cheer'`,
/// 공지·이벤트는 본문 HTML 의 `<a href="/cheer">`.
/// 그래서 라우팅 표는 여기 하나만 두고 네 곳이 전부 이걸 부른다
/// (예전엔 각자 "내부 식별자는 이 앱에 대상 화면이 없어 무시" 하고 버렸다).
///
/// 새 목적지를 열려면 [_screens] 에 한 줄 + 콘솔 select 에 같은 값을 넣는다.
///
/// 로그인이 필요한 화면(계정 관리)은 넣지 않는다 — 비로그인 유저가 눌렀을 때
/// 빈 화면이 뜨는 게 아무 일도 안 일어나는 것보다 나쁘다.
const _screens = <String, WidgetBuilder>{
  '/cheer': _cheer,
  '/garage': _garage,
  '/fuel-reports': _fuelReports,
  '/events': _events,
  '/notices': _notices,
  '/inbox': _inbox,
  '/my-reports': _myReports,
  '/faq': _faq,
  '/policies': _policies,
  '/settings': _settings,
};

/// 위젯을 여기서 직접 못 만드는 화면 — 라우터가 Riverpod ref·픽커 등을 주입한다.
/// 생성 로직을 복붙하면 소스가 둘로 갈리므로 GoRouter 경로로 넘긴다.
const _routerPaths = <String>{'/inquiry'};

Widget _cheer(BuildContext _) => const CheerScreen();
Widget _garage(BuildContext _) => const GarageScreen();
Widget _fuelReports(BuildContext _) => const FuelReportScreen();
Widget _events(BuildContext _) => const EventsScreen();
Widget _notices(BuildContext _) => const NoticesScreen();
Widget _inbox(BuildContext _) => const InboxScreen();
Widget _myReports(BuildContext _) => const MyReportsScreen();
Widget _faq(BuildContext _) => const FaqScreen();
Widget _policies(BuildContext _) => const PoliciesScreen();
Widget _settings(BuildContext _) => const SettingsScreen();

/// 내부 식별자로 볼 링크인지. 콘솔이 `/cheer` 처럼 슬래시로 시작하게 넣는다.
/// 이걸로 걸러야 `launchUrl('/cheer')` 같은 무의미한 외부 호출을 막는다.
bool isInternalLink(String url) => url.startsWith('/');

/// 등록된 내부 화면이면 이동하고 true, 모르는 식별자면 아무것도 안 하고 false
/// (호출부가 외부 링크로 폴백할지 스스로 정한다).
///
/// push 를 기다리지 않는다 — 기다리면 '그 화면이 닫힐 때까지' 블록돼서
/// 호출부의 뒷정리(팝업 닫기 등)가 화면이 닫힌 뒤에야 실행된다.
bool openInternalLink(BuildContext context, String url) {
  final path = _normalize(url);
  final builder = _screens[path];
  if (builder != null) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: builder));
    return true;
  }
  if (_routerPaths.contains(path)) {
    context.push(path);
    return true;
  }
  return false;
}

String _normalize(String url) => url.split('?').first.trim();
