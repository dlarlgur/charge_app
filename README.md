# ⛽🔋 주유/충전 도우미

주유소 + 전기차 충전소 통합 앱 (com.dksw.charge)

## 프로젝트 구조

```
charge_app/
├── lib/                          # Flutter 앱 소스
│   ├── main.dart                 # 엔트리포인트
│   ├── app.dart                  # MaterialApp + 테마 + 라우터
│   ├── core/
│   │   ├── theme/
│   │   │   ├── app_colors.dart   # 전체 컬러 시스템 (Gas Blue + EV Green)
│   │   │   └── app_theme.dart    # Light/Dark ThemeData
│   │   └── constants/
│   │       └── api_constants.dart # API URL, 코드, 앱 상수
│   ├── data/
│   │   ├── models/
│   │   │   └── models.dart       # GasStation, EvStation, Charger, Filter 등
│   │   └── services/
│   │       ├── api_service.dart   # Dio HTTP 클라이언트
│   │       └── location_service.dart # GPS 위치
│   ├── providers/
│   │   └── providers.dart         # Riverpod 상태관리 전체
│   ├── router/
│   │   └── app_router.dart        # GoRouter 라우팅
│   └── ui/
│       ├── splash/                # 스플래시 (Blue→Green 로고)
│       ├── permission/            # 위치 권한 요청
│       ├── onboarding/            # 3단계 온보딩 (차종→유종/충전기→반경)
│       ├── home/                  # 메인 (⛽주유/🔋충전 탭 + 리스트)
│       ├── detail/
│       │   ├── gas_detail_screen.dart  # 주유소 상세
│       │   └── ev_detail_screen.dart   # 충전소 상세 (충전기 현황 카드)
│       ├── settings/              # 설정
│       └── widgets/
│           └── shared_widgets.dart # 카드, 칩, 요약카드, 배지, 탭바 등
│
├── server/                        # Node.js API 프록시 서버
│   ├── index.js                   # Express 서버 엔트리
│   ├── package.json
│   ├── .env.example               # 환경변수 템플릿
│   ├── routes/
│   │   ├── gas.js                 # /api/stations/gas/*
│   │   ├── ev.js                  # /api/stations/ev/*
│   │   └── prices.js              # /api/prices/*
│   ├── services/
│   │   ├── opinet.js              # 오피넷 API 래퍼
│   │   ├── evApi.js               # 환경부 EV API 래퍼
│   │   └── coordinate.js          # WGS84 ↔ KATEC 좌표변환 (proj4)
│   └── middleware/
│       └── cache.js               # 인메모리 캐시
│
├── assets/
│   └── logo.svg                   # 앱 로고 (Blue→Green 그라디언트)
│
├── pubspec.yaml                   # Flutter 의존성
├── android_manifest_template.xml  # Android 설정 템플릿
└── ios_info_plist_additions.xml   # iOS 설정 추가 항목
```

## 세팅 가이드

### 1. API Key 발급

#### 오피넷 (주유소)
1. https://www.opinet.co.kr 접속 → 회원가입
2. 유가관련정보 → 유가정보 API → 무료 API 이용 신청
3. 발급받은 Key 저장

#### 환경부 전기차 충전소
1. https://www.data.go.kr 접속 → 회원가입
2. "한국환경공단_전기자동차 충전소 정보" 검색
3. 활용신청 → API Key 발급

#### 카카오맵 SDK
1. https://developers.kakao.com 접속 → 앱 등록
2. 플랫폼 > Android: com.dksw.charge + 키해시 등록
3. 플랫폼 > iOS: 번들 ID 등록
4. 네이티브 앱 키 저장

### 2. 서버 실행

```bash
cd server
cp .env.example .env
# .env 파일에 API Key 입력

npm install
npm run dev    # 개발 (nodemon)
# 또는
npm start      # 프로덕션
```

서버가 http://localhost:3000 에서 실행됩니다.

### 3. Flutter 앱 실행

```bash
# 프로젝트 생성 (최초 1회)
flutter create --org com.dksw --project-name charge_helper .

# 의존성 설치
flutter pub get

# 코드 생성 (Riverpod generator 등)
dart run build_runner build --delete-conflicting-outputs

# 실행
flutter run
```

### 4. Android 설정

`android/app/src/main/AndroidManifest.xml` 에 android_manifest_template.xml 내용 반영

`android/app/build.gradle`:
```gradle
android {
    namespace "com.dksw.charge"
    defaultConfig {
        applicationId "com.dksw.charge"
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

### 5. iOS 설정

`ios/Runner/Info.plist` 에 ios_info_plist_additions.xml 내용 추가

## API 엔드포인트

| Method | Endpoint | 설명 | 캐시 |
|--------|----------|------|------|
| GET | /api/stations/gas/around | 반경 내 주유소 | 5분 |
| GET | /api/stations/gas/:id | 주유소 상세 | 10분 |
| GET | /api/stations/ev/around | 반경 내 충전소 | 30분 |
| GET | /api/stations/ev/status | 충전기 실시간 상태 | 1분 |
| GET | /api/stations/ev/:id | 충전소 상세 | 10분 |
| GET | /api/prices/gas/average | 전국 평균 유가 | 30분 |
| GET | /api/prices/gas/lowest | 최저가 TOP 10 | 5분 |
| GET | /api/health | 서버 상태 | - |

## 기술 스택

- **Frontend**: Flutter 3.x (Dart), Riverpod, GoRouter, Dio, Hive
- **Backend**: Node.js, Express, proj4 (좌표변환)
- **API**: 오피넷 (KATEC) + 환경부 (WGS84)
- **Cache**: 인메모리 (Redis 옵션)
- **Map**:네이버지도 Flutter SDK
