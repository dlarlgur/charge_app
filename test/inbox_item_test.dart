import 'package:flutter_test/flutter_test.dart';
import 'package:charge_helper/data/services/inbox_service.dart';

/// 만료 판정이 틀리면 멀쩡한 기프티콘이 회색으로 죽거나, 만료된 걸 들고 매장에 간다.
void main() {
  InboxItem at(String? d) =>
      InboxItem(id: 1, type: 'coupon', title: 't', expiresAt: d);

  final today = DateTime.now();
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  test('기한 없으면 만료 아님', () {
    expect(at(null).expired, isFalse);
    expect(at(null).daysLeft, isNull);
  });

  test('오늘 만료면 아직 유효 (당일까지 쓴다)', () {
    final i = at(fmt(today));
    expect(i.expired, isFalse);
    expect(i.daysLeft, 0);
  });

  test('어제 만료면 만료', () {
    expect(at(fmt(today.subtract(const Duration(days: 1)))).expired, isTrue);
  });

  test('12일 남으면 D-12', () {
    expect(at(fmt(today.add(const Duration(days: 12)))).daysLeft, 12);
  });

  test('형식이 깨지면 만료로 오판하지 않는다', () {
    expect(at('언젠가').expired, isFalse);
  });
}
