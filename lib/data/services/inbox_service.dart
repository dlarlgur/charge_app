import 'package:dio/dio.dart';
import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'auth_service.dart';

/// 소식함 한 건 — 관리자 메시지 또는 쿠폰.
class InboxItem {
  final int id;
  final String type; // 'message' | 'coupon'
  final String title;
  final String? body;
  final String? couponBrand;
  final String? couponCode;
  final bool hasImage;
  final String? expiresAt; // 'YYYY-MM-DD'
  final bool read;
  final bool used;

  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.couponBrand,
    this.couponCode,
    this.hasImage = false,
    this.expiresAt,
    this.read = false,
    this.used = false,
  });

  bool get isCoupon => type == 'coupon';

  /// 만료일이 지났는지 — 지난 쿠폰도 목록에서 지우지 않고 회색 처리한다.
  /// 만료일 **당일까지는 유효**하다(매장에서 그날 쓸 수 있다).
  bool get expired {
    if (expiresAt == null) return false;
    final d = DateTime.tryParse(expiresAt!);
    if (d == null) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// 'D-12' 칩용. 만료됐거나 기한이 없으면 null.
  int? get daysLeft {
    if (expiresAt == null || expired) return null;
    final d = DateTime.tryParse(expiresAt!);
    if (d == null) return null;
    final now = DateTime.now();
    return d.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: (j['id'] as num).toInt(),
        type: j['type']?.toString() ?? 'message',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString(),
        couponBrand: j['couponBrand']?.toString(),
        couponCode: j['couponCode']?.toString(),
        hasImage: j['hasImage'] == true,
        expiresAt: j['expiresAt']?.toString(),
        read: j['read'] == true,
        used: j['used'] == true,
      );
}

class InboxService {
  InboxService._();
  static final instance = InboxService._();

  final _dio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl))
    ..transformer = BackgroundTransformer();

  /// 안 읽은 개수 — 설정 타일 뱃지와 도착 배너가 같은 값을 본다.
  final ValueNotifier<int> unread = ValueNotifier(0);

  Future<Options> _auth() async {
    final access = await AuthService.accessToken();
    return Options(headers: {
      'x-device-id': DkswCore.deviceId,
      if (access != null) 'Authorization': 'Bearer $access',
    });
  }

  /// 바코드 이미지 URL + 헤더 — Image.network 에 그대로 넘긴다.
  /// 정적 URL 이 아니라 인증이 필요하다(바코드는 현금이라 공개 경로에 못 둔다).
  String imageUrl(int id) => '${ApiConstants.baseUrl}/inbox/$id/image';

  Future<Map<String, String>> imageHeaders() async {
    final access = await AuthService.accessToken();
    return {if (access != null) 'Authorization': 'Bearer $access'};
  }

  Future<List<InboxItem>> list({int? cursor}) async {
    try {
      final res = await _dio.get('/inbox',
          queryParameters: {if (cursor != null) 'cursor': cursor},
          options: await _auth());
      return ((res.data['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 뱃지 갱신. 실패는 조용히 — 소식함 하나 때문에 화면이 깨지면 안 된다.
  Future<void> refreshUnread() async {
    try {
      final res = await _dio.get('/inbox/unread-count', options: await _auth());
      unread.value = (res.data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      /* 기존 값 유지 */
    }
  }

  Future<void> markRead(int id) async {
    try {
      await _dio.post('/inbox/$id/read', options: await _auth());
      if (unread.value > 0) unread.value = unread.value - 1;
    } catch (_) {}
  }

  Future<void> markUsed(int id, bool used) async {
    try {
      await _dio.post('/inbox/$id/used',
          data: {'used': used}, options: await _auth());
    } catch (_) {}
  }
}
