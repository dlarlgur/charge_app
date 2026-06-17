import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dksw_app_core/dksw_app_core.dart';

/// 로그인 사용자 (서버 users 레코드).
class AuthUser {
  final int id;
  final String? email;
  final String? nickname;
  final String? profileImageUrl;

  const AuthUser({required this.id, this.email, this.nickname, this.profileImageUrl});

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] as num).toInt(),
        email: j['email'] as String?,
        nickname: j['nickname'] as String?,
        profileImageUrl: j['profile_image_url'] as String?,
      );
}

/// 소셜 로그인(카카오/네이버/구글) → charge_server 인증 → JWT 보관.
/// 식별/쿼터는 서버가 (provider,uid)→userId 로 처리. 토큰은 secure storage.
class AuthService {
  AuthService._();

  static const _base = 'https://charge.dksw4.com/api';
  // 구글 서버검증용 Web client ID (serverClientId). idToken 의 aud 가 됨.
  static const _googleWebClientId =
      '108426301015-ceas7b2r6e3nmsmi08upbdg58pt8k6nv.apps.googleusercontent.com';

  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _storage = FlutterSecureStorage();
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // ── 프로바이더 토큰 획득 ──
  static Future<String?> _kakaoToken() async {
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk();
      } catch (_) {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }
    return token.accessToken;
  }

  static Future<String?> _naverToken() async {
    final res = await FlutterNaverLogin.logIn();
    final token = res.accessToken?.accessToken;
    return (token != null && token.isNotEmpty) ? token : null;
  }

  static Future<String?> _googleToken() async {
    final gs = GoogleSignIn(serverClientId: _googleWebClientId, scopes: const ['email']);
    final acc = await gs.signIn(); // 취소 시 null
    if (acc == null) return null;
    final auth = await acc.authentication;
    return auth.idToken; // 서버가 tokeninfo 로 검증
  }

  /// 소셜 로그인 → 서버 → JWT 저장 → AuthUser. 취소/실패 시 null.
  static Future<AuthUser?> login(String provider) async {
    String? token;
    switch (provider) {
      case 'kakao':
        token = await _kakaoToken();
        break;
      case 'naver':
        token = await _naverToken();
        break;
      case 'google':
        token = await _googleToken();
        break;
    }
    if (token == null) return null;

    final res = await _dio.post('/auth/$provider', data: {
      'token': token,
      'deviceId': DkswCore.deviceId,
      'package': 'com.dksw.charge',
    });
    final d = res.data as Map;
    if (d['ok'] != true) return null;
    await _storage.write(key: _kAccess, value: d['access'] as String?);
    await _storage.write(key: _kRefresh, value: d['refresh'] as String?);
    return AuthUser.fromJson(Map<String, dynamic>.from(d['user'] as Map));
  }

  /// 저장된 토큰으로 현재 사용자 조회 (앱 시작 시). 만료면 refresh 1회 시도.
  static Future<AuthUser?> currentUser() async {
    final access = await _storage.read(key: _kAccess);
    if (access == null) return null;
    try {
      final res = await _dio.get('/auth/me',
          options: Options(headers: {'Authorization': 'Bearer $access'}));
      if (res.data['ok'] == true) {
        return AuthUser.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && await _refresh()) {
        return currentUser();
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _refresh() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null) return false;
    try {
      final res = await _dio.post('/auth/refresh', data: {'refresh': refresh});
      if (res.data['ok'] == true) {
        await _storage.write(key: _kAccess, value: res.data['access'] as String?);
        await _storage.write(key: _kRefresh, value: res.data['refresh'] as String?);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 서버 인증 호출용 access 토큰 (만료 시 refresh). AI 쿼터 등 보호 API 호출에 사용.
  static Future<String?> accessToken() async {
    final access = await _storage.read(key: _kAccess);
    return access;
  }

  static Future<void> logout() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    try { await UserApi.instance.logout(); } catch (_) {}
    try { await FlutterNaverLogin.logOut(); } catch (_) {}
    try { await GoogleSignIn().signOut(); } catch (_) {}
  }

  /// 회원탈퇴 — 서버 개인정보 파기 후 로컬 토큰 삭제.
  static Future<void> withdraw() async {
    final access = await _storage.read(key: _kAccess);
    if (access != null) {
      try {
        await _dio.delete('/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $access'}));
      } catch (_) {}
    }
    await logout();
  }
}

/// 인증 상태 — 마이페이지/로그인화면이 watch.
class AuthNotifier extends StateNotifier<AuthUser?> {
  AuthNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    state = await AuthService.currentUser();
  }

  /// 로그인 성공 시 true.
  Future<bool> login(String provider) async {
    final u = await AuthService.login(provider);
    if (u != null) state = u;
    return u != null;
  }

  Future<void> logout() async {
    await AuthService.logout();
    state = null;
  }

  Future<void> withdraw() async {
    await AuthService.withdraw();
    state = null;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthUser?>((ref) => AuthNotifier());
