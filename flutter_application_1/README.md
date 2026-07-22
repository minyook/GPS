# 🌺 동백전 위치 방문 확인 및 FCM 알림 통신 가이드 (README)

이 문서는 플러터(Flutter) 클라이언트와 FastAPI 백엔드 간에 화면(UI) 없이 **"실시간 위치 수집 ➡️ 백엔드 전송 ➡️ 방문 확인 ➡️ FCM 푸시 알림 발송"**만 핵심 모듈로 떼어내서 개발할 때 참고하는 개발 가이드라인입니다.

---

## 📡 1. 플러터 앱 (Flutter App) - 통신 & 알림 핵심 모듈

화면 없이 백그라운드 수집과 알림 수신만 처리할 때 사용하는 핵심 파일 및 함수 구조입니다.

### ① 알림 초기화 및 수신 채널 설정
- **위치**: [lib/services/fcm_service.dart](file:///c:/flutter/flutter_application_1/lib/services/fcm_service.dart)
- **핵심 함수**:
  - `initLocalNotifications()`: 폰 상단 헤드업 알림을 띄우기 위한 채널 설정 및 초기화
  - `firebaseMessagingBackgroundHandler()`: 앱이 꺼져 있거나 백그라운드일 때 수신된 FCM 푸시 알림 처리

### ② 백그라운드 위치 측정 및 서버 전송 (30초 주기)
- **위치**: [lib/services/background_service.dart](file:///c:/flutter/flutter_application_1/lib/services/background_service.dart)
- **핵심 함수**:
  - `performLocationCheck()`: 30초마다 실제 GPS를 측정하여 백엔드 `POST /api/location`으로 HTTP POST 요청 발송
  - `initializeBackgroundService()`: 안드로이드 포어그라운드 서비스 및 무음 채널(`silent_background_channel`) 설정

### ③ 디바이스 FCM 토큰 백엔드 등록 및 리스너 연결 (통신 전용 통합 모듈 ⭐)
- **위치**: [lib/services/fcm_setup_helper.dart](file:///c:/flutter/flutter_application_1/lib/services/fcm_setup_helper.dart)
- **핵심 클래스**: `FcmSetupHelper`
  - `setupFcm()`: 기기 FCM 권한 획득, 토큰 획득 및 갱신 리스너 등록, Foreground 수신 팝업 노출, 클릭 핸들링 통합 구동

---

## 🖥️ 2. FastAPI 백엔드 (FastAPI) - 수신 & 푸시 전송 핵심 모듈

수신된 데이터 기반으로 방문을 판단하여 구글 파이어베이스 서버로 알림을 쏘는 핵심 파일 및 함수 구조입니다.

### ① FCM 토큰 관리 서비스
- **위치**: `app/services/user_service.py`
- **핵심 함수**:
  - `register_fcm_token()`: 클라이언트로부터 전달받은 FCM 토큰을 메모리 캐시(`G_FCM_TOKENS`) 및 DB에 등록

### ② 위치 정보 수신 및 방문 판단
- **위치**: `app/services/location_service.py`
- **핵심 함수**:
  - `process_location_update()`: 30초마다 전송된 GPS 좌표를 수신하여 가맹점 반경(50m) 내 방문 여부를 연산하고 FCM 발송 트리거 호출

### ③ FCM 푸시 알림 실제 발송 (Firebase Admin SDK)
- **위치**: `app/services/fcm_service.py`
- **핵심 함수**:
  - `process_and_send_visit_notification()`: `firebase_admin.messaging.send(message)`를 직접 사용하여 사용자의 폰 상단으로 진짜 동백전 팝업 푸시 알림을 즉시 발송

---

## 🛠️ 3. 💡 앱 화면(UI) 없이 백그라운드 수집 통신 구조만 떼어내서 쓰는 방법

나중에 실제 상용 앱에 탑재할 때는 지도나 UI 화면을 다 빼고, 앱이 실행될 때 백그라운드 데몬(Daemon)으로만 가동되게 분리할 수 있습니다.

### 1) 화면(UI) 의존성 완전 제거
- `lib/screens/main_screen.dart`는 필요하지 않으므로 삭제합니다.
   
### 2) 백그라운드 서비스 및 FCM 헬퍼 결합 가동
- `lib/main.dart`의 `main()` 함수에서 아래와 같이 포어그라운드 스위치 없이 백그라운드 서비스와 FCM 헬퍼를 즉시 자동 시작합니다:
  ```dart
  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(); // Firebase 초기화
    
    await initLocalNotifications(); // 로컬 알림 초기화
    
    // 1. FCM 디바이스 토큰 자동 획득 및 백엔드 등록 & 리스너 가동
    await FcmSetupHelper.setupFcm(); 
    
    // 2. 백그라운드 30초 수집 서비스 자동 시작
    await initializeBackgroundService();
    await FlutterBackgroundService().startService(); 
    
    runApp(const MyApp());
  }
  ```

---

## 🔗 4. 클라이언트 ↔ 서버 API 데이터 통신 규격

### 1) FCM 토큰 등록 API (POST)
- **Endpoint**: `POST /api/user/fcm-token`
- **Request Body**:
  ```json
  {
    "user_id": "test_user_flutter",
    "fcm_token": "fcm_token_string_here..."
  }
  ```

### 2) 위치 정보 전송 API (POST)
- **Endpoint**: `POST /api/location`
- **Request Body**:
  ```json
  {
    "user_id": "test_user_flutter",
    "latitude": 35.179558,
    "longitude": 129.075642,
    "accuracy": 15.0
  }
  ```

### 3) 백엔드 FCM 발송 메시지 규격 (Payload)
- **FCM Message Object**:
  ```json
  {
    "notification": {
      "title": "💳 [가맹점명] (동백전 가맹점)",
      "body": "현재 [가맹점명] 가맹점에 방문 중입니다! 동백전으로 결제하고 스탬프를 적립해 보세요 🎁"
    },
    "data": {
      "store_id": "store_999",
      "type": "STAMP_EVENT_ALERT",
      "click_action": "FLUTTER_NOTIFICATION_CLICK"
    }
  }
  ```

---

## 🛠️ 5. 🚀 기존 상용 프로젝트에 이 기능을 이식(합칠)할 때의 필수 4단계 체크리스트

나중에 본인의 기존 Flutter 프로젝트에 이 방문 수집 & FCM 알림 통신 시스템을 안전하게 이식하기 위해 꼭 가져가야 하는 필수 설정 가이드입니다.

### 1단계: 패키지 의존성 이식 (`pubspec.yaml`)
기존 프로젝트의 `pubspec.yaml` 파일에 아래 패키지들을 그대로 추가합니다:
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0                       # 백엔드 API 통신용
  geolocator: ^11.0.0                 # 실시간 GPS 센서 좌표 획득용
  firebase_core: ^2.27.0              # 파이어베이스 코어
  firebase_messaging: ^14.7.19        # FCM 푸시 알림 연동용
  flutter_local_notifications: ^17.0.0 # 상단 헤드업 푸시 팝업 노출용
  flutter_background_service: ^5.0.9  # 30초 백그라운드 수집 유지용
  workmanager: ^0.9.0                 # 앱이 꺼졌을 때 OS 예약 수집용
  permission_handler: ^11.3.0         # GPS '항상 허용' 권한 요청용
```

### 2단계: 안드로이드 네이티브 권한 및 컴포넌트 이식 (`AndroidManifest.xml`)
안드로이드의 백그라운드 백터 서비스 유지를 위해 기존 프로젝트의 `android/app/src/main/AndroidManifest.xml`에 아래 퍼미션과 컴포넌트 설정을 복사해 넣습니다:
- **필수 권한 (Manifest 상단)**:
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  ```
- **백그라운드 수집 서비스 및 부팅 리시버 등록 (`<application>` 태그 내부)**:
  ```xml
  <service
      android:name="id.flutter.flutter_background_service.BackgroundService"
      android:foregroundServiceType="location"
      android:enabled="true"
      android:exported="true" />

  <receiver
      android:name="id.flutter.flutter_background_service.BootReceiver"
      android:enabled="true"
      android:exported="true">
      <intent-filter>
          <action android:name="android.intent.action.BOOT_COMPLETED" />
          <action android:name="android.intent.action.QUICKBOOT_POWERON" />
      </intent-filter>
  </receiver>
  ```

### 3단계: 안드로이드 SDK 빌드 버전 상향 (`android/app/build.gradle.kts`)
최신 안드로이드 백그라운드 위치 서비스 동작 보장을 위해 기존 프로젝트 빌드 타겟 버전을 상향 조정합니다:
- **수정 위치**: `android/app/build.gradle.kts`
  ```kotlin
  android {
      compileSdk = 36 // compileSdk 버전을 36 이상으로 변경
      defaultConfig {
          minSdk = 23
          targetSdk = 35 // targetSdk 버전을 35 이상으로 변경
      }
  }
  ```

### 4단계: 파이어베이스 설정 및 파일 주입
- 기존 프로젝트의 `android/app/` 폴더 내부에 본인 파이어베이스 프로젝트에서 발급한 **`google-services.json`** 파일을 배치합니다.
- `lib/firebase_options.dart` 파일을 복사해 넣어 파이어베이스 초기화가 가능하도록 구성합니다.
- 이식이 끝났으면 `lib/services/` 폴더 아래에 생성해 둔 아래 3개 파일만 복사해서 붙여넣으시면 됩니다.
  1. `fcm_service.dart` (알림 채널)
  2. `background_service.dart` (위치 수집)
  3. `fcm_setup_helper.dart` (통합 연동 API 헬퍼)
