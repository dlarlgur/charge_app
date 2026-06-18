import 'dart:convert';

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
  final bool signupCompleted; // 닉네임·약관동의까지 끝낸 "완성" 계정 여부.
  final String? ageGroup; // 연령대(10대/20대/…/60대이상). 네이버 자동 또는 수동 입력.

  const AuthUser({
    required this.id,
    this.email,
    this.nickname,
    this.profileImageUrl,
    this.signupCompleted = false,
    this.ageGroup,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] as num).toInt(),
        email: j['email'] as String?,
        nickname: j['nickname'] as String?,
        profileImageUrl: j['profile_image_url'] as String?,
        signupCompleted: j['signup_completed'] == 1 || j['signup_completed'] == true,
        ageGroup: j['age_group'] as String?,
      );
}

/// 같은 이메일이 다른 소셜로 이미 가입돼 있을 때 — login() 이 throw.
class EmailInUseException implements Exception {
  final String provider; // 기존 가입 프로바이더(kakao/naver/google)
  EmailInUseException(this.provider);
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
    if (res.status.name != 'loggedIn') {
      // 취소는 조용히 null, 그 외 실패는 사유 노출.
      if (res.errorMessage == null || res.errorMessage!.isEmpty) return null;
      throw Exception('naver status=${res.status.name}, msg=${res.errorMessage}');
    }
    // 이 플러그인(Android)은 logIn() 결과에 토큰을 안 담아오는 경우가 있다.
    // → loggedIn이면 getCurrentAccessToken()으로 별도 조회해 보강.
    var token = res.accessToken?.accessToken ?? '';
    if (token.isEmpty) {
      final t = await FlutterNaverLogin.getCurrentAccessToken();
      token = t.accessToken;
    }
    if (token.isEmpty) {
      throw Exception('naver: loggedIn인데 토큰을 못 받음(getCurrentAccessToken도 empty)');
    }
    return token;
  }

  static Future<String?> _googleToken() async {
    final gs = GoogleSignIn(serverClientId: _googleWebClientId, scopes: const ['email']);
    final acc = await gs.signIn(); // 취소 시 null
    if (acc == null) return null;
    final auth = await acc.authentication;
    return auth.idToken; // 서버가 tokeninfo 로 검증
  }

  /// 소셜 로그인 → 서버 → JWT 저장. 취소/실패 시 user=null.
  /// isNew=true 면 신규 가입 → 앱이 회원가입 완료 화면(닉네임/이메일/동의) 띄움.
  static Future<({AuthUser? user, bool isNew})> login(String provider) async {
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
    if (token == null) return (user: null, isNew: false);

    Response res;
    try {
      res = await _dio.post('/auth/$provider', data: {
        'token': token,
        'deviceId': DkswCore.deviceId,
        'package': 'com.dksw.charge',
      });
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 409 && data is Map && data['error'] == 'email_in_use') {
        throw EmailInUseException((data['provider'] as String?) ?? '');
      }
      rethrow;
    }
    final d = res.data as Map;
    if (d['ok'] != true) return (user: null, isNew: false);
    await _storage.write(key: _kAccess, value: d['access'] as String?);
    await _storage.write(key: _kRefresh, value: d['refresh'] as String?);
    return (
      user: AuthUser.fromJson(Map<String, dynamic>.from(d['user'] as Map)),
      isNew: d['isNew'] == true,
    );
  }

  /// 회원가입 완료 화면에서 닉네임/이메일/연령대 저장.
  static Future<AuthUser?> updateProfile({String? nickname, String? email, String? ageGroup}) async {
    final access = await _storage.read(key: _kAccess);
    if (access == null) return null;
    try {
      final res = await _dio.patch(
        '/auth/me',
        data: {
          if (nickname != null) 'nickname': nickname,
          if (email != null) 'email': email,
          if (ageGroup != null) 'age_group': ageGroup,
        },
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
      if (res.data['ok'] == true) {
        return AuthUser.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
      }
    } catch (_) {}
    return null;
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

  /// 서버 인증 호출용 access 토큰. 만료(또는 만료 임박)면 refresh 로 자동 갱신 후 반환.
  static Future<String?> accessToken() async {
    final access = await _storage.read(key: _kAccess);
    if (access == null) return null;
    if (_isExpired(access)) {
      final ok = await _refresh();
      if (!ok) return null;
      return _storage.read(key: _kAccess);
    }
    return access;
  }

  /// JWT exp 로컬 디코드 — 만료 60초 전이면 true(갱신 대상).
  /// 파싱 실패나 exp 없음은 false(만료 아님으로 간주, 서버가 401 주면 다른 경로서 처리).
  static bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      var p = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (p.length % 4 != 0) {
        p += '=';
      }
      final payload = jsonDecode(utf8.decode(base64.decode(p))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= (exp - 60);
    } catch (_) {
      return false;
    }
  }

  static Future<void> logout() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    try { await UserApi.instance.logout(); } catch (_) {}
    try { await FlutterNaverLogin.logOut(); } catch (_) {}
    try { await GoogleSignIn().signOut(); } catch (_) {}
  }

  /// 회원탈퇴 — 서버 개인정보 파기 + 소셜 연결 완전 해제 + 로컬 토큰 삭제.
  /// 소셜 unlink/disconnect 로 다음 로그인 시 동의화면이 다시 뜬다(완전 연결해제).
  static Future<void> withdraw() async {
    final access = await _storage.read(key: _kAccess);
    if (access != null) {
      try {
        await _dio.delete('/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $access'}));
      } catch (_) {}
    }
    try { await UserApi.instance.unlink(); } catch (_) {}
    try { await GoogleSignIn().disconnect(); } catch (_) {}
    try { await FlutterNaverLogin.logOut(); } catch (_) {}
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

  /// 로그인 → { ok: 성공여부, isNew: 신규가입여부 }. 신규면 회원가입 완료 화면으로.
  Future<({bool ok, bool isNew})> login(String provider) async {
    final r = await AuthService.login(provider);
    if (r.user != null) state = r.user;
    return (ok: r.user != null, isNew: r.isNew);
  }

  /// 프로필(닉네임/이메일) 갱신 후 상태 반영.
  void setUser(AuthUser user) => state = user;

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
