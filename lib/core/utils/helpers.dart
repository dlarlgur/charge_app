import 'dart:math';

import 'package:intl/intl.dart';

/// 정수 천 단위 콤마 (홈 요약 카드 등). 소수는 버림(truncate), NaN/∞ 는 0.
String formatThousandsInt(num value) {
  if (value is double && (value.isNaN || value.isInfinite)) {
    return NumberFormat('#,###', 'ko_KR').format(0);
  }
  return NumberFormat('#,###', 'ko_KR').format(value.truncate());
}

/// API 숫자 필드(PRICE/DIFF 등)가 num 또는 문자열로 올 때 안전하게 파싱
double parseApiDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    return double.tryParse(t) ?? 0;
  }
  return 0;
}

/// 가격 포맷 (1,234원)
String formatPrice(double price) {
  return '${price.toInt().toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  )}원';
}

/// kWh 가격 포맷 (292원/kWh)
String formatEvPrice(double price) {
  return '${price.toInt()}원/kWh';
}

/// 거리 포맷 (800m / 1.2Km)
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toInt()}m';
  return '${(meters / 1000).toStringAsFixed(1)}Km';
}

/// 두 좌표 간 거리 (미터) - Haversine
double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _toRad(double deg) => deg * pi / 180;

/// 시간 전 텍스트 (방금, 3분 전, 2시간 전)
String timeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}

/// 지역코드 → 지역명 매핑 (오피넷)
const sidoMap = {
  '01': '서울', '02': '경기', '03': '강원',
  '04': '충북', '05': '충남', '06': '전북',
  '07': '전남', '08': '경북', '09': '경남',
  '10': '부산', '11': '제주', '12': '대구',
  '13': '인천', '14': '광주', '15': '대전',
  '16': '울산', '17': '세종',
};
