import 'package:dio/dio.dart';

/// 429(rate_limited) 응답이면 사용자용 한도 초과 문구를 반환, 아니면 null.
/// [feature] 예: 'AI 주유소 추천', 'AI 충전소 추천'.
/// 일일 한도면 서버가 준 limit(N)으로 "오늘 … N회를 모두 사용하셨어요" 안내.
String? rateLimitMessage(Object? error, {required String feature}) {
  if (error is DioException && error.response?.statusCode == 429) {
    final data = error.response?.data;
    final window = (data is Map) ? data['window'] : null;
    final limitRaw = (data is Map) ? data['limit'] : null;
    final n = (limitRaw is num && limitRaw > 0) ? limitRaw.toInt() : null;
    if (window == 'day') {
      return n != null
          ? '오늘 $feature 횟수 $n회를 모두 사용하셨어요.\n내일 다시 이용해주세요.'
          : '오늘 $feature를 모두 사용하셨어요.\n내일 다시 이용해주세요.';
    }
    return '$feature 요청이 많아요.\n잠시 후 다시 시도해주세요.';
  }
  return null;
}
