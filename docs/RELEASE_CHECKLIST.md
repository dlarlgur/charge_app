# 출시 전 체크리스트

스토어 업로드 직전 반드시 확인해야 할 항목들.

## AdMob (광고)

- [ ] **AndroidManifest.xml App ID 교체**
  - 위치: `android/app/src/main/AndroidManifest.xml:141`
  - 현재: `ca-app-pub-3940256099942544~3347511713` (Google 테스트 ID)
  - 교체값: AdMob 콘솔에서 발급한 실제 App ID (`ca-app-pub-8640148276009977~...`)
  - 미교체 시 위험: AdMob 정책 위반으로 계정 정지 가능
- [ ] **iOS Info.plist `GADApplicationIdentifier` 추가/교체**
  - iOS 도 발급 후 동일하게 prod ID 로
- [ ] **iOS unit IDs 발급**
  - 위치: `lib/data/services/ad_service.dart:13-14` (TODO 마크 됨)
  - 현재: Android 슬롯 재사용 → iOS 출시 시 잘못 서빙됨
  - 작업: 네이티브/배너/리워드 각각 iOS unit ID 발급해 교체
- [ ] **테스트 디바이스 ID 제거 또는 prod 코드에서 비활성**
  - 출시 빌드는 실제 광고 노출
- [ ] **광고 표시 빈도 검증**
  - 전면 광고/팝업 광고가 사용자 흐름 막지 않는지

## 빌드/서명

- [ ] **release keystore 백업** (잃으면 같은 패키지로 업데이트 불가)
  - 위치: `android/key.properties` 가 가리키는 storeFile
  - 안전한 곳 (1Password / 외부 저장) 에 복사
- [ ] **versionCode/versionName bump**
  - `pubspec.yaml` `version: x.y.z+N` — 빌드마다 +N 증가
- [ ] **`flutter build apk --release` + `--split-per-abi`** 검토
  - 단일 APK 보다 split 으로 다운로드 사이즈 감소
- [ ] **`minifyEnabled` + `shrinkResources` 활성화 검토**
  - 현재 OFF — 켜려면 ProGuard 룰 먼저 정비 (Firebase, naver_map 등 reflection 사용 plugin 보호 룰)
  - 미정비 상태 그대로 켜면 release runtime crash 가능

## 시크릿/키

- [ ] **NaverMap Client ID 검증**
  - `android/gradle.properties` `NAVER_MAP_CLIENT_ID=...`
  - 미설정 시 fallback `x57z7zsj7i` 사용 — prod 에선 정식 ID 필수
- [ ] **Firebase 구성 파일** (`google-services.json`) — prod 프로젝트의 것인지
- [ ] **API base URL 확인** (`lib/core/constants/api_constants.dart`)
  - dev/staging/prod 분기 있다면 prod 로

## 권한/manifest

- [ ] **불필요 권한 제거** — AndroidManifest 의 권한이 실제 사용 기능과 일치하는지
- [ ] **위치 권한 사용 목적 문구** (`AndroidManifest`/`Info.plist`)
  - Play Console / App Store 심사에서 요구

## 로깅

- [ ] **debugPrint / print 잔존 확인**
  - `grep -rn "print(" lib/ | grep -v debugPrint` → 0건이어야 함
  - 현재 services/ 는 깨끗 ✓ (이번 라운드에서 정리)
- [ ] **release 빌드 로그 노출 점검**
  - `LogInterceptor` 등은 이미 `kDebugMode` 가드 적용됨 ✓

## 백엔드

- [ ] **API base URL** 가 prod 서버 가리키는지
- [ ] **prod 서버 모니터링/알람** 설정 — error rate, latency, 5xx
- [ ] **DB 백업 정책** 확인

## 스토어 메타데이터

- [ ] 스크린샷 (light/dark 모드 둘 다)
- [ ] 앱 설명문 (한글)
- [ ] 개인정보처리방침 URL
- [ ] 만 16세 미만 데이터 수집 여부 표시

## 출시 후

- [ ] **단계적 출시** (10% → 50% → 100%) 활용
- [ ] **크래시리포팅 모니터링** (Firebase Crashlytics 등)
- [ ] **AdMob 수익 정상 발생 확인** (실제 App ID 적용 확인)
