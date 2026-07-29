import 'dart:convert';

import 'package:dksw_app_core/dksw_app_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/api_constants.dart';
import 'alert_service.dart';
import 'charger_memo_service.dart';
import 'favorite_service.dart';
import 'place_service.dart';
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
    final aliases = (remote['aliases'] as List?) ?? const [];
    final chargerMemos = (remote['chargerMemos'] as List?) ?? const [];
    final prefs = (remote['prefs'] as Map?) ?? const {};
    final places = (remote['places'] as List?) ?? const [];
    final hasRemote = vehicles.isNotEmpty ||
        places.isNotEmpty ||
        favorites.isNotEmpty ||
        alarms.isNotEmpty ||
        aliases.isNotEmpty ||
        chargerMemos.isNotEmpty ||
        prefs['vehicleType'] != null ||
        prefs['marketingConsent'] == true ||
        // AI 동의/경로 엔진만 저장된 계정도 '원격 데이터 있음'으로 봐야 한다.
        // 빠져 있으면 import 분기로 가서 서버 값을 복원하지 않아 "동의가 풀렸다"로 보임.
        prefs['aiTextConsent'] is bool ||
        prefs['routeEngine'] != null;
    if (hasRemote) {
      await _applyRemote(prefs, vehicles, favorites, alarms, aliases, chargerMemos);
      if (places.isNotEmpty) await PlaceService.applyRemote(places);
    } else {
      await UserSyncService.instance.import(buildLocalSnapshot());
    }
  }

  static Future<void> _applyRemote(Map prefs, List vehicles, List favorites, List alarms, List aliases, List chargerMemos) async {
    final box = Hive.box(AppConstants.settingsBox);

    // 기본 차량설정(서버 우선)
    if (prefs['vehicleType'] != null) {
      box.put(AppConstants.keyVehicleType, prefs['vehicleType']);
      // 서버에 차량설정이 있다 = 이 계정은 온보딩을 완료함 → 재로그인/데이터삭제 후 온보딩 스킵.
      box.put(AppConstants.keyOnboardingDone, true);
    }
    if (prefs['fuelType'] != null) {
      box.put(AppConstants.keyFuelType, prefs['fuelType']);
    }
    // 홈 유종 필터 복원 — 멀티선택 목록(fuelTypes)이 있으면 그대로, 없으면
    // (구 데이터) 설정 유종 단일값으로 폴백. 이게 빠지면 재설치 후 설정은
    // 고급유인데 홈은 기본값 휘발유로 보여 "저장이 풀렸다"로 보임 (사용자 제보).
    final remoteFuels = (prefs['fuelTypes'] is List)
        ? (prefs['fuelTypes'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    if (remoteFuels.isNotEmpty) {
      box.put(AppConstants.keyGasFilterFuelTypes, remoteFuels);
    } else if (prefs['fuelType'] != null) {
      box.put(AppConstants.keyGasFilterFuelTypes, [prefs['fuelType']]);
    }

    // 마케팅 동의 — 서버 값을 이 기기(콘솔 device)에 그대로 반영 (true/false 양방향).
    // true 만 재적용하던 단방향 래칫은 '다른 기기/직전 세션에서 끈 상태'가 재로그인 때
    // 다시 켜지는 버그의 원인 (서버 false 를 기기에 안 내려서 로컬 true 가 살아남음).
    if (prefs['marketingConsent'] is bool) {
      final want = prefs['marketingConsent'] == true;
      if (DkswCore.consentAgreed('marketing') != want) {
        final m = DkswCore.signupConsents.firstWhere(
          (c) => c.key == 'marketing',
          orElse: () => const SignupConsent(key: 'marketing', title: '마케팅 정보 수신', required: false, version: '1.0'),
        );
        await DkswCore.postConsents([ConsentChoice(key: 'marketing', agreed: want, version: m.version)]);
      }
    }

    // AI 문구 생성 동의 — 서버 값 복원 (NULL=미선택이면 로컬 유지)
    if (prefs['aiTextConsent'] is bool) {
      box.put(AppConstants.keyAiThirdPartyConsent, prefs['aiTextConsent']);
    }
    // AI 경로 기준 내비 복원 (tmap|naver|kakao)
    final re = prefs['routeEngine']?.toString();
    if (re == 'tmap' || re == 'naver' || re == 'kakao') {
      box.put('route_engine', re);
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
      box.put(AppConstants.keyAiOnboardingDone, true); // 차량 복원됨 → AI 온보딩 스킵
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
    }

    // 별칭 복원 (즐겨찾기 여부 무관, mirror:false 로 루프 방지)
    for (final a in aliases.whereType<Map>()) {
      final id = (a['stationId'] ?? '').toString();
      final type = (a['type'] ?? '').toString();
      final alias = (a['alias'] ?? '').toString();
      if (id.isEmpty || type.isEmpty || alias.isEmpty) continue;
      await StationAliasService.set(id, alias, type: type, mirror: false);
    }

    // 충전기 메모 복원 (mirror:false 로 루프 방지)
    for (final m in chargerMemos.whereType<Map>()) {
      final id = (m['stationId'] ?? '').toString();
      final chger = (m['chgerId'] ?? '').toString();
      final memo = (m['memo'] ?? '').toString();
      if (id.isEmpty || chger.isEmpty || memo.isEmpty) continue;
      await ChargerMemoService.set(id, chger, memo, mirror: false);
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
      // 홈 유종 필터 멀티선택 — 게스트 시절 골라둔 목록도 회원 이관에 포함
      'fuelTypes': List<String>.from(
          box.get(AppConstants.keyGasFilterFuelTypes, defaultValue: const <String>[])),
      'marketingConsent': DkswCore.consentAgreed('marketing') == true,
      // AI 문구 동의 — 게스트 시절 선택도 회원 이관 (미선택 null 은 서버가 무시)
      'aiTextConsent': box.get(AppConstants.keyAiThirdPartyConsent),
      // AI 경로 기준 내비 — 게스트 시절 선택도 이관
      'routeEngine': box.get('route_engine'),
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

    return {
      'prefs': prefs,
      'vehicles': vehicles,
      'favorites': favorites,
      'alarms': alarms,
      'aliases': StationAliasService.allEntries(),
      'chargerMemos': ChargerMemoService.allEntries(),
      'places': PlaceService.toSnapshotList(),
    };
  }
}
