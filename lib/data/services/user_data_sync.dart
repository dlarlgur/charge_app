import 'dart:convert';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import 'alert_service.dart';
import 'favorite_service.dart';
import 'station_alias_service.dart';
import 'user_sync_service.dart';

/// 로그인/회원가입 시점의 회원 데이터 동기화 글루.
/// - 서버에 데이터가 있으면 로컬에 적용(union, 무손실) + 알람 재구독 + 마케팅 동의 재적용
/// - 서버가 비어있고 로컬에 데이터가 있으면 로컬 스냅샷 이관(import)
class UserDataSync {
  /// 로그인/가입 완료 직후 호출. 비로그인/실패 시 조용히 종료.
  static Future<void> run() async {
    final remote = await UserSyncService.instance.sync();
    if (remote == null) return;
    final vehicles = (remote['vehicles'] as List?) ?? const [];
    final favorites = (remote['favorites'] as List?) ?? const [];
    final alarms = (remote['alarms'] as List?) ?? const [];
    final prefs = (remote['prefs'] as Map?) ?? const {};
    final hasRemote = vehicles.isNotEmpty ||
        favorites.isNotEmpty ||
        alarms.isNotEmpty ||
        prefs['vehicleType'] != null ||
        prefs['marketingConsent'] == true;
    if (hasRemote) {
      await _applyRemote(prefs, vehicles, favorites, alarms);
    } else {
      await UserSyncService.instance.import(buildLocalSnapshot());
    }
  }

  static Future<void> _applyRemote(Map prefs, List vehicles, List favorites, List alarms) async {
    final box = Hive.box(AppConstants.settingsBox);

    // 기본 차량설정(서버 우선)
    if (prefs['vehicleType'] != null) {
      box.put(AppConstants.keyVehicleType, prefs['vehicleType']);
      // 서버에 차량설정이 있다 = 이 계정은 온보딩을 완료함 → 재로그인/데이터삭제 후 온보딩 스킵.
      box.put(AppConstants.keyOnboardingDone, true);
    }
    if (prefs['fuelType'] != null) box.put(AppConstants.keyFuelType, prefs['fuelType']);

    // 마케팅 동의 — 이 기기(콘솔 device)로 재적용
    if (prefs['marketingConsent'] == true) {
      final m = DkswCore.signupConsents.firstWhere(
        (c) => c.key == 'marketing',
        orElse: () => const SignupConsent(key: 'marketing', title: '마케팅 정보 수신', required: false, version: '1.0'),
      );
      await DkswCore.postConsents([ConsentChoice(key: 'marketing', agreed: true, version: m.version)]);
    }

    // AI 차량 — 서버를 소스로 ai_vehicles 갱신
    if (vehicles.isNotEmpty) {
      final list = vehicles.whereType<Map>().map((v) => {
            'id': v['clientId'],
            'name': v['name'] ?? '',
            'vehicleType': v['kind'] ?? 'gas',
            'fuelType': v['fuelType'] ?? 'B027',
            'tankCapacity': v['tankCapacity'] ?? 55.0,
            'efficiency': v['efficiency'] ?? 12.5,
            'batteryCapacity': v['batteryCapacity'] ?? 64.0,
            'evEfficiency': v['evEfficiency'] ?? 5.0,
            'currentLevelPercent': v['currentLevelPercent'] ?? 25.0,
            'targetMode': v['targetMode'] ?? 'FULL',
            'targetValue': v['targetValue'] ?? 50000.0,
            'targetChargePercent': v['targetChargePercent'] ?? 80.0,
          }).toList();
      box.put(AppConstants.keyAiVehicles, jsonEncode(list));
      final sel = vehicles.whereType<Map>().firstWhere((v) => v['isSelected'] == true, orElse: () => vehicles.first as Map);
      if (sel['clientId'] != null) box.put(AppConstants.keyAiSelectedVehicleId, sel['clientId']);
    }

    // 즐겨찾기 — union(로컬 보존, 없는 것만 추가)
    for (final f in favorites.whereType<Map>()) {
      final id = (f['stationId'] ?? '').toString();
      final type = (f['type'] ?? '').toString();
      if (id.isEmpty || type.isEmpty) continue;
      if (!FavoriteService.isFavorite(id, type)) {
        FavoriteService.add(
          id: id, type: type,
          name: (f['name'] ?? '').toString(), subtitle: (f['subtitle'] ?? '').toString(),
          extra: f['brand'] != null ? {'brand': f['brand']} : null,
        );
      }
      final alias = (f['alias'] ?? '').toString();
      if (alias.isNotEmpty) await StationAliasService.set(id, alias, type: type);
    }

    // 알람 — 현재 기기로 재구독(device 테이블 등록)
    for (final a in alarms.whereType<Map>()) {
      final id = (a['stationId'] ?? '').toString();
      final type = (a['type'] ?? '').toString();
      if (id.isEmpty) continue;
      if (type == 'gas') {
        final fuels = (a['fuelTypes'] ?? '').toString().split(',').where((s) => s.isNotEmpty).toList();
        if (fuels.isNotEmpty) {
          await AlertService().subscribeMultiple(stationId: id, stationName: (a['name'] ?? '').toString(), fuelTypes: fuels);
        }
      } else if (type == 'ev') {
        await AlertService().subscribeEvAlarm(stationId: id, stationName: (a['name'] ?? '').toString());
      }
    }
  }

  /// 게스트→회원 이관용 로컬 스냅샷.
  static Map<String, dynamic> buildLocalSnapshot() {
    final box = Hive.box(AppConstants.settingsBox);

    final prefs = {
      'vehicleType': box.get(AppConstants.keyVehicleType),
      'fuelType': box.get(AppConstants.keyFuelType),
      'marketingConsent': DkswCore.consentAgreed('marketing') == true,
    };

    List vlist;
    try {
      final raw = box.get(AppConstants.keyAiVehicles);
      vlist = (raw is String && raw.isNotEmpty) ? (jsonDecode(raw) as List) : const [];
    } catch (_) {
      vlist = const [];
    }
    final selected = box.get(AppConstants.keyAiSelectedVehicleId);
    final vehicles = vlist.whereType<Map>().map((m) => {
          'clientId': m['id'],
          'name': m['name'],
          'kind': m['vehicleType'],
          'fuelType': m['fuelType'],
          'tankCapacity': m['tankCapacity'],
          'efficiency': m['efficiency'],
          'targetMode': m['targetMode'],
          'targetValue': m['targetValue'],
          'batteryCapacity': m['batteryCapacity'],
          'evEfficiency': m['evEfficiency'],
          'targetChargePercent': m['targetChargePercent'],
          'currentLevelPercent': m['currentLevelPercent'],
          'isSelected': m['id'] == selected,
        }).toList();

    final favorites = FavoriteService.getAll().map((f) {
      final id = (f['id'] ?? '').toString();
      final type = (f['type'] ?? '').toString();
      return {
        'type': type, 'stationId': id,
        'name': f['name'], 'subtitle': f['subtitle'], 'brand': f['brand'],
        'alias': StationAliasService.get(id, type: type),
      };
    }).toList();

    final svc = AlertService();
    final alarms = <Map<String, dynamic>>[];
    for (final id in svc.subscribedStationIds) {
      alarms.add({'type': 'gas', 'stationId': id, 'fuelTypes': svc.subscribedFuelTypes(id).join(','), 'name': svc.subscribedStationNames[id] ?? ''});
    }
    for (final id in svc.evAlarmStationIds) {
      alarms.add({'type': 'ev', 'stationId': id, 'name': svc.evAlarmNames[id] ?? ''});
    }

    return {'prefs': prefs, 'vehicles': vehicles, 'favorites': favorites, 'alarms': alarms};
  }
}
