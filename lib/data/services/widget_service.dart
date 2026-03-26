import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../services/api_service.dart';

/// 홈 위젯 데이터 갱신 서비스
///
/// Flutter → SharedPreferences → Android AppWidgetProvider 순으로 데이터 전달.
/// home_widget 패키지가 "flutter." 접두사로 SharedPreferences에 저장함.
class WidgetService {
  WidgetService._();

  static const _appGroupId = 'group.com.dksw.charge'; // iOS App Group (필요 시)

  static final _timeFmt = DateFormat('HH:mm', 'ko_KR');

  /// 앱 초기화 시 한 번 호출
  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// 즐겨찾기 주유소 위젯 데이터를 갱신하고 위젯을 업데이트
  static Future<void> updateGasWidget() async {
    try {
      final box = Hive.isBoxOpen(AppConstants.favoritesBox)
          ? Hive.box(AppConstants.favoritesBox)
          : await Hive.openBox(AppConstants.favoritesBox);

      // 즐겨찾기 주유소 최대 3개 (gas 타입)
      final gasFavs = box.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((f) => f['type'] == 'gas')
          .toList()
        ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));

      final settingsBox = Hive.isBoxOpen(AppConstants.settingsBox)
          ? Hive.box(AppConstants.settingsBox)
          : await Hive.openBox(AppConstants.settingsBox);
      final fuelCode = settingsBox.get(AppConstants.keyAiFuelType,
          defaultValue: FuelType.gasoline.code) as String;
      final fuelLabel = FuelType.fromCode(fuelCode).label;

      final items = <Map<String, dynamic>>[];

      for (final fav in gasFavs.take(3)) {
        final id = fav['id'] as String? ?? '';
        if (id.isEmpty) continue;
        try {
          final detail = await ApiService().getGasStationDetail(id);
          final station = GasStation.fromJson(detail);
          items.add({
            'name': station.name,
            'brand': station.brand,
            'price': station.price.toInt(),
            'isSelf': station.isSelf,
            'fuelLabel': fuelLabel,
          });
        } catch (_) {
          // API 실패 시 즐겨찾기 이름만 표시
          items.add({
            'name': fav['name'] ?? '',
            'brand': '',
            'price': 0,
            'isSelf': false,
            'fuelLabel': fuelLabel,
          });
        }
      }

      final updatedAt = _timeFmt.format(DateTime.now());

      await HomeWidget.saveWidgetData('widget_gas_list', jsonEncode(items));
      await HomeWidget.saveWidgetData('widget_gas_updated', updatedAt);
      await HomeWidget.updateWidget(androidName: 'GasWidgetProvider');
    } catch (e) {
      // 위젯 업데이트 실패는 무시 (앱 동작에 영향 없음)
    }
  }

  /// 즐겨찾기 충전소 위젯 데이터를 갱신하고 위젯을 업데이트
  static Future<void> updateEvWidget() async {
    try {
      final box = Hive.isBoxOpen(AppConstants.favoritesBox)
          ? Hive.box(AppConstants.favoritesBox)
          : await Hive.openBox(AppConstants.favoritesBox);

      // 즐겨찾기 충전소 최대 3개 (ev 타입)
      final evFavs = box.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((f) => f['type'] == 'ev')
          .toList()
        ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));

      final items = <Map<String, dynamic>>[];

      for (final fav in evFavs.take(3)) {
        final id = fav['id'] as String? ?? '';
        if (id.isEmpty) continue;
        try {
          final detail = await ApiService().getEvStationDetail(id);
          final station = EvStation.fromJson(detail);

          final hasFast = station.chargers.any((c) {
            final out = c.output;
            return out >= 50;
          });
          final maxKw = station.chargers.isEmpty
              ? 0
              : station.chargers.map((c) => c.output).reduce((a, b) => a > b ? a : b);
          final brokenCount = station.offlineCount;

          // statusCode: 0=available, 1=busy(no slots), 2=broken
          final statusCode = brokenCount >= station.totalCount && station.totalCount > 0
              ? 2
              : station.availableCount == 0
                  ? 1
                  : 0;

          items.add({
            'name': station.name,
            'available': station.availableCount,
            'total': station.totalCount,
            'broken': brokenCount,
            'hasFast': hasFast,
            'maxKw': maxKw,
            'statusCode': statusCode,
          });
        } catch (_) {
          items.add({
            'name': fav['name'] ?? '',
            'available': 0,
            'total': 0,
            'broken': 0,
            'hasFast': false,
            'maxKw': 0,
            'statusCode': 0,
          });
        }
      }

      final updatedAt = _timeFmt.format(DateTime.now());

      await HomeWidget.saveWidgetData('widget_ev_list', jsonEncode(items));
      await HomeWidget.saveWidgetData('widget_ev_updated', updatedAt);
      await HomeWidget.updateWidget(androidName: 'EvWidgetProvider');
    } catch (e) {
      // 위젯 업데이트 실패는 무시
    }
  }

  /// 두 위젯 모두 갱신
  static Future<void> updateAll() async {
    await Future.wait([updateGasWidget(), updateEvWidget()]);
  }

  /// WorkManager 백그라운드 태스크에서 호출
  /// Hive / API 초기화가 필요한 환경이므로 독립적으로 실행 가능
  static Future<bool> backgroundUpdateGas() async {
    try {
      await Hive.initFlutter();
      if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
        await Hive.openBox(AppConstants.settingsBox);
      }
      if (!Hive.isBoxOpen(AppConstants.favoritesBox)) {
        await Hive.openBox(AppConstants.favoritesBox);
      }
      await updateGasWidget();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> backgroundUpdateEv() async {
    try {
      await Hive.initFlutter();
      if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
        await Hive.openBox(AppConstants.settingsBox);
      }
      if (!Hive.isBoxOpen(AppConstants.favoritesBox)) {
        await Hive.openBox(AppConstants.favoritesBox);
      }
      await updateEvWidget();
      return true;
    } catch (_) {
      return false;
    }
  }
}
