import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/models.dart';
import '../services/api_service.dart';
import '../services/station_alias_service.dart';

/// 홈 위젯 데이터 갱신 서비스
///
/// Flutter → SharedPreferences("HomeWidgetPreferences") → Android AppWidgetProvider.
/// home_widget 0.6.x 는 키에 접두사를 붙이지 않고 그대로 저장한다.
class WidgetService {
  WidgetService._();

  static const _appGroupId = 'group.com.dksw.charge'; // iOS App Group (필요 시)

  // locale 미지정 — 'HH:mm' 는 locale 영향 없고, 'ko_KR' 명시 시 initializeDateFormatting()
  // 호출 안 된 환경(WorkManager isolate 포함) 에서 LocaleDataException 으로 throw 됨.
  static final _timeFmt = DateFormat('HH:mm');

  /// 앱 초기화 시 한 번 호출
  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
    // 위젯 새로고침 버튼 → 백그라운드 isolate 콜백 등록
    await HomeWidget.registerInteractivityCallback(backgroundCallback);
  }

  /// 즐겨찾기 주유소 위젯 데이터를 갱신하고 위젯을 업데이트
  static Future<void> updateGasWidget() async {
    try {
      debugPrint('[Widget][gas] start');
      final box = Hive.isBoxOpen(AppConstants.favoritesBox)
          ? Hive.box(AppConstants.favoritesBox)
          : await Hive.openBox(AppConstants.favoritesBox);
      debugPrint('[Widget][gas] favoritesBox size=${box.length}');

      final gasFavs = box.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((f) => f['type'] == 'gas')
          .toList()
        ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));
      debugPrint('[Widget][gas] gasFavs=${gasFavs.length} ids=${gasFavs.map((f) => f['id']).toList()}');

      final settingsBox = Hive.isBoxOpen(AppConstants.settingsBox)
          ? Hive.box(AppConstants.settingsBox)
          : await Hive.openBox(AppConstants.settingsBox);
      final fuelCode = settingsBox.get(AppConstants.keyAiFuelType,
          defaultValue: FuelType.gasoline.code) as String;
      final fuelLabel = FuelType.fromCode(fuelCode).label;

      final items = <Map<String, dynamic>>[];

      for (final fav in gasFavs.take(4)) {
        final id = (fav['id'] as String? ?? '').trim();
        final favName = (fav['name'] ?? '').toString();
        final favBrand = (fav['brand'] ?? '').toString();
        if (id.isEmpty) {
          // id 빈 항목도 fallback 표시 — 위젯이 빈 상태로 빠지지 않도록
          debugPrint('[Widget][gas] empty id, fallback name="$favName"');
          items.add({
            'id': '', 'name': favName, 'brand': favBrand,
            'price': 0, 'isSelf': false, 'fuelLabel': fuelLabel,
          });
          continue;
        }
        try {
          final detail = await ApiService().getGasStationDetail(id);
          final station = GasStation.fromJson(detail);
          String resolvedName;
          try {
            resolvedName = StationAliasService.resolveGas(id, station.name);
          } catch (e) {
            debugPrint('[Widget][gas] resolveGas throw: $e — use raw name');
            resolvedName = station.name;
          }
          items.add({
            'id': id, 'name': resolvedName, 'brand': station.brand,
            'price': station.price.toInt(), 'isSelf': station.isSelf,
            'fuelLabel': fuelLabel,
          });
        } catch (e) {
          debugPrint('[Widget][gas] detail API fail id=$id: $e — fallback to fav name');
          String resolvedName;
          try {
            resolvedName = StationAliasService.resolveGas(id, favName);
          } catch (_) {
            resolvedName = favName;
          }
          items.add({
            'id': id, 'name': resolvedName, 'brand': favBrand,
            'price': 0, 'isSelf': false, 'fuelLabel': fuelLabel,
          });
        }
      }

      // 가스: price 오름차순 (저렴한 순) — row1 이 항상 best
      // price=0(데이터 없음) 은 뒤로
      items.sort((a, b) {
        final pa = (a['price'] as int? ?? 0);
        final pb = (b['price'] as int? ?? 0);
        if (pa == 0 && pb == 0) return 0;
        if (pa == 0) return 1;
        if (pb == 0) return -1;
        return pa.compareTo(pb);
      });

      final updatedAt = _timeFmt.format(DateTime.now());
      final json = jsonEncode(items);
      debugPrint('[Widget][gas] items=${items.length} payload=$json');

      await HomeWidget.saveWidgetData('widget_gas_list', json);
      await HomeWidget.saveWidgetData('widget_gas_updated', updatedAt);
      await HomeWidget.updateWidget(androidName: 'GasWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'CombinedWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'GasSmallWidgetProvider');
      debugPrint('[Widget][gas] save+update OK');
    } catch (e, st) {
      debugPrint('[Widget][gas] FAIL $e\n$st');
    }
  }

  /// 즐겨찾기 충전소 위젯 데이터를 갱신하고 위젯을 업데이트
  static Future<void> updateEvWidget() async {
    try {
      debugPrint('[Widget][ev] start');
      final box = Hive.isBoxOpen(AppConstants.favoritesBox)
          ? Hive.box(AppConstants.favoritesBox)
          : await Hive.openBox(AppConstants.favoritesBox);
      debugPrint('[Widget][ev] favoritesBox size=${box.length}');

      final evFavs = box.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((f) => f['type'] == 'ev')
          .toList()
        ..sort((a, b) => (b['addedAt'] ?? '').compareTo(a['addedAt'] ?? ''));
      debugPrint('[Widget][ev] evFavs=${evFavs.length} ids=${evFavs.map((f) => f['id']).toList()}');

      final items = <Map<String, dynamic>>[];

      for (final fav in evFavs.take(4)) {
        final id = (fav['id'] as String? ?? '').trim();
        final favName = (fav['name'] ?? '').toString();
        if (id.isEmpty) {
          debugPrint('[Widget][ev] empty id, fallback name="$favName"');
          items.add({
            'id': '', 'name': favName,
            'available': 0, 'total': 0, 'broken': 0,
            'hasFast': false, 'maxKw': 0, 'statusCode': 0,
          });
          continue;
        }
        try {
          final detail = await ApiService().getEvStationDetail(id);
          final station = EvStation.fromJson(detail);

          final hasFast = station.chargers.any((c) => c.output >= 50);
          final maxKw = station.chargers.isEmpty
              ? 0
              : station.chargers.map((c) => c.output).reduce((a, b) => a > b ? a : b);
          final brokenCount = station.offlineCount;

          final statusCode = brokenCount >= station.totalCount && station.totalCount > 0
              ? 2
              : station.availableCount == 0
                  ? 1
                  : 0;

          String resolvedName;
          try {
            resolvedName = StationAliasService.resolveEv(id, station.name);
          } catch (e) {
            debugPrint('[Widget][ev] resolveEv throw: $e — use raw name');
            resolvedName = station.name;
          }

          items.add({
            'id': id, 'name': resolvedName,
            'available': station.availableCount, 'total': station.totalCount,
            'broken': brokenCount, 'hasFast': hasFast, 'maxKw': maxKw,
            'statusCode': statusCode,
          });
        } catch (e) {
          debugPrint('[Widget][ev] detail API fail id=$id: $e — fallback to fav name');
          String resolvedName;
          try {
            resolvedName = StationAliasService.resolveEv(id, favName);
          } catch (_) {
            resolvedName = favName;
          }
          items.add({
            'id': id, 'name': resolvedName,
            'available': 0, 'total': 0, 'broken': 0,
            'hasFast': false, 'maxKw': 0, 'statusCode': 0,
          });
        }
      }

      // EV: available 내림차순 (가용 많은 순) — row1 이 항상 best
      items.sort((a, b) {
        final aa = (a['available'] as int? ?? 0);
        final ab = (b['available'] as int? ?? 0);
        return ab.compareTo(aa);
      });

      final updatedAt = _timeFmt.format(DateTime.now());
      final json = jsonEncode(items);
      debugPrint('[Widget][ev] items=${items.length} payload=$json');

      await HomeWidget.saveWidgetData('widget_ev_list', json);
      await HomeWidget.saveWidgetData('widget_ev_updated', updatedAt);
      await HomeWidget.updateWidget(androidName: 'EvWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'CombinedWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'EvSmallWidgetProvider');
      debugPrint('[Widget][ev] save+update OK');
    } catch (e, st) {
      debugPrint('[Widget][ev] FAIL $e\n$st');
    }
  }

  /// 두 위젯 모두 갱신
  static Future<void> updateAll() async {
    await Future.wait([updateGasWidget(), updateEvWidget()]);
  }

  /// home_widget 위젯 새로고침 버튼 클릭 시 백그라운드 isolate 에서 호출.
  /// uri host: refresh_gas | refresh_ev | refresh_all
  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    try {
      debugPrint('[Widget][refresh] callback host=${uri?.host} uri=$uri');
      await Hive.initFlutter();
      for (final box in [
        AppConstants.settingsBox,
        AppConstants.favoritesBox,
        'station_aliases',
      ]) {
        if (!Hive.isBoxOpen(box)) await Hive.openBox(box);
      }
      final host = uri?.host ?? '';
      final touchGas = host == 'refresh_gas' || host != 'refresh_ev';
      final touchEv = host == 'refresh_ev' || host != 'refresh_gas';

      // 즉시 피드백 — 시간 칸을 "갱신 중…" 으로
      if (touchGas) {
        await HomeWidget.saveWidgetData('widget_gas_updated', '갱신 중…');
        await HomeWidget.updateWidget(androidName: 'GasWidgetProvider');
        await HomeWidget.updateWidget(androidName: 'CombinedWidgetProvider');
      }
      if (touchEv) {
        await HomeWidget.saveWidgetData('widget_ev_updated', '갱신 중…');
        await HomeWidget.updateWidget(androidName: 'EvWidgetProvider');
      }

      // 실제 재요청
      if (host == 'refresh_gas') {
        await updateGasWidget();
      } else if (host == 'refresh_ev') {
        await updateEvWidget();
      } else {
        await updateAll();
      }
    } catch (e, st) {
      debugPrint('[Widget][refresh] FAIL $e\n$st');
    }
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
