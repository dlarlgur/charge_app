import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/api_constants.dart';

enum UpdateType { none, optional, forced }

class VersionCheckResult {
  final UpdateType type;
  final String latestVersion;
  final String releaseNote;

  const VersionCheckResult({
    required this.type,
    required this.latestVersion,
    required this.releaseNote,
  });
}

class VersionService {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 서버에서 최신 버전 문자열만 반환 (설정 화면 표시용)
  static Future<String> fetchLatestVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Platform.isAndroid ? 'ANDROID' : 'IOS';
      final res = await _dio.get(ApiConstants.appVersion, queryParameters: {
        'app': info.packageName,
        'platform': platform,
      });
      return (res.data['data']['latest_version'] as String?) ?? info.version;
    } catch (_) {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    }
  }

  static Future<VersionCheckResult?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Platform.isAndroid ? 'ANDROID' : 'IOS';
      final packageName = info.packageName;
      final currentCode = int.tryParse(info.buildNumber) ?? 0;

      debugPrint('[VersionService] 버전 체크 시작');
      debugPrint('[VersionService] packageName: $packageName');
      debugPrint('[VersionService] platform: $platform');
      debugPrint('[VersionService] currentCode: $currentCode');

      final res = await _dio.get(ApiConstants.appVersion, queryParameters: {
        'app': packageName,
        'platform': platform,
      });

      debugPrint('[VersionService] 응답: ${res.data}');

      final data = res.data['data'] as Map<String, dynamic>;
      final latestCode = (data['latest_version_code'] as num).toInt();
      final minCode = (data['min_version_code'] as num).toInt();
      final forceUpdate = (data['force_update'] as num).toInt() == 1;
      final latestVersion = data['latest_version'] as String;
      final releaseNote = (data['release_note'] as String?) ?? '';

      debugPrint('[VersionService] latestCode: $latestCode, minCode: $minCode, forceUpdate: $forceUpdate');
      debugPrint('[VersionService] 비교: currentCode($currentCode) vs latestCode($latestCode)');

      if (currentCode >= latestCode) {
        debugPrint('[VersionService] 결과: 업데이트 불필요 (최신 버전)');
        return VersionCheckResult(type: UpdateType.none, latestVersion: latestVersion, releaseNote: releaseNote);
      }
      if (currentCode < minCode || forceUpdate) {
        debugPrint('[VersionService] 결과: 강제 업데이트 필요');
        return VersionCheckResult(type: UpdateType.forced, latestVersion: latestVersion, releaseNote: releaseNote);
      }
      debugPrint('[VersionService] 결과: 선택 업데이트 가능');
      return VersionCheckResult(type: UpdateType.optional, latestVersion: latestVersion, releaseNote: releaseNote);
    } catch (e, stackTrace) {
      debugPrint('[VersionService] 오류: $e');
      debugPrint('[VersionService] 스택트레이스: $stackTrace');
      return null;
    }
  }
}
